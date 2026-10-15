from datetime import datetime, timedelta, timezone
import http.client
import json
from pathlib import Path
import tempfile
import threading
import unittest
from urllib.error import HTTPError
from urllib.parse import quote, urlsplit
import xml.etree.ElementTree as ET

from watch.store import connect


FIXTURES = Path(__file__).parent / 'fixtures' / 'pm'
NOW = datetime(2026, 10, 15, 16, tzinfo=timezone.utc)
BASE = 'https://www.pm.gc.ca/en/news/'
CALGARY = 'media-advisories/2026/10/14/thursday-october-15-2026'


def fixture(name):
    return (FIXTURES / name).read_text()


def rss_items():
    return ET.fromstring(fixture('news.rss')).findall('./channel/item')


class PmDataTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.data = Path(self.temp.name)

    def parse(self, name):
        from watch.pm.itinerary import parse_itinerary
        return parse_itinerary(fixture('itinerary-' + name + '.html'))

    def seed(self):
        from watch.pm.sources import save_item
        with connect(self.data) as db, db:
            for day in (14, 15, 16):
                save_item(db, BASE + f'media-advisories/2026/10/{day-1}/day-{day}',
                          f'Thursday, October {day}, 2026', '2026-10-14T21:00:00Z',
                          '<p>Private meetings</p><h2>Calgary, Alberta</h2>'
                          '<p><strong>9:15 a.m.</strong> First meeting.</p>'
                          '<p><strong>12:30 p.m.</strong> Second meeting.</p>',
                          'rss', lambda url: fixture('nominatim-calgary.json').encode(), lambda n: None, NOW)
            for n in range(3):
                save_item(db, BASE + f'readouts/2026/10/14/item-{n}', f'Readout {n}',
                          f'2026-10-14T23:0{n}:00Z', '<p>Hello <em>Canada</em>.</p>',
                          'rss', None, None, NOW)

    def server(self):
        from watch.api import make_server
        server = make_server(self.data, '127.0.0.1', 0, clock=lambda: NOW)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()

        def close():
            server.shutdown()
            server.server_close()
            thread.join()
        self.addCleanup(close)
        return server

    def get(self, server, path):
        conn = http.client.HTTPConnection('127.0.0.1', server.server_port, timeout=3)
        conn.request('GET', path)
        response = conn.getresponse()
        status, body = response.status, json.loads(response.read())
        conn.close()
        return status, body

    def test_01_calgary(self):
        parsed = self.parse('thursday-october-15-2026')
        self.assertEqual(len(parsed['events']), 4)
        event = parsed['events'][0]
        self.assertEqual((event['local_time'], event['place'], event['media']),
                         ('09:15', 'Calgary, Alberta', 'open'))
        self.assertEqual(parsed['notes'], [])

    def test_02_multi_country(self):
        events = self.parse('wednesday-september-16-2026')['events']
        self.assertEqual(list(dict.fromkeys(e['place'] for e in events)),
                         ['Strasbourg, France', 'Manchester, United Kingdom', 'Liverpool, United Kingdom'])
        self.assertEqual((events[0]['local_time'], events[0]['media']), ('06:00', 'pool'))
        self.assertEqual(events[-1]['place'], 'Manchester, United Kingdom')

    def test_03_question_period(self):
        events = {e['local_time']: e for e in self.parse('monday-september-21-2026')['events']}
        self.assertIn('Question Period', events['14:15']['text'])
        self.assertEqual(events['14:15']['venue'], 'West Block, Parliament Hill')
        self.assertEqual(events['16:20']['media'], 'closed')

    def test_04_washington(self):
        events = self.parse('tuesday-may-6-2025')['events']
        self.assertGreaterEqual(len(events), 1)
        self.assertEqual(events[0]['place'], 'Washington, D.C., United States of America')

    def test_05_update_and_rss(self):
        from watch.pm.itinerary import parse_itinerary
        self.assertEqual(len(self.parse('update-wednesday-november-5-2025')['events']), 3)
        item = next(i for i in rss_items() if i.findtext('title') == 'Thursday, October 15, 2026')
        self.assertEqual(parse_itinerary(item.findtext('description')), self.parse('thursday-october-15-2026'))
        self.assertEqual(parse_itinerary('<p>Private meetings</p>'), {'notes': ['Private meetings'], 'events': []})
        self.assertEqual(parse_itinerary('<h2>Ottawa, Ontario</h2><p>noon Meeting.</p>')['events'][0]['local_time'], '12:00')

    def test_06_saint_pierre(self):
        from watch.pm.zones import zone_for
        place = self.parse('sunday-september-20-2026')['events'][0]['place']
        self.assertEqual(zone_for(place, None, None), 'America/Miquelon')

    def test_07_zones(self):
        from watch.pm.zones import zone_for
        for heading, lat, lon, expected in [
            ('Calgary, Alberta', None, None, 'America/Edmonton'),
            ('National Capital Region, Canada', None, None, 'America/Toronto'),
            ('Washington, D.C., United States of America', None, None, 'America/New_York'),
            ('Los Angeles, United States of America', 34.05, -118.24, 'America/Los_Angeles'),
            ('Strasbourg, France', None, None, 'Europe/Paris'),
            ('Sherbrooke, Québec', None, None, 'America/Toronto'),
            ('The Hague, the Netherlands', None, None, 'Europe/Amsterdam'),
            ('Busan, Republic of Korea', None, None, 'Asia/Seoul'),
            ('Singapore, Republic of Singapore', None, None, 'Asia/Singapore'),
            ('Riga, Latvia', None, None, 'Europe/Riga'),
            ('Atlantis, Nowhere', None, None, None),
        ]:
            with self.subTest(heading=heading):
                self.assertEqual(zone_for(heading, lat, lon), expected)

    def test_08_starts_at(self):
        from watch.pm.sources import starts_at
        self.assertEqual(starts_at('2026-10-15', '09:15', 'America/Edmonton'), '2026-10-15T15:15:00Z')
        self.assertIsNone(starts_at('2026-10-15', '09:15', None))

    def test_09_place_id(self):
        from watch.pm.places import place_id
        self.assertEqual(place_id('Place__Name'), 'place-name')
        self.assertEqual(place_id('Washington, D.C., United States of America'),
                         'washington-d-c-united-states-of-america')

    def test_10_place_cache(self):
        from watch.pm.places import lookup
        calls, sleeps = [], []

        def fetch(url):
            calls.append(url)
            return fixture('nominatim-calgary.json').encode()
        with connect(self.data) as db, db:
            self.assertEqual(lookup(db, 'Calgary, Alberta', fetch, sleeps.append)['lat'], 51.0456064)
            self.assertEqual(len(calls), 1)
            calls.clear()
            self.assertEqual(lookup(db, 'Calgary, Alberta', fetch, sleeps.append)['zone'], 'America/Edmonton')
            self.assertEqual(calls, [])
            self.assertEqual(lookup(db, 'National Capital Region, Canada', fetch, sleeps.append)['lat'], 45.4215)
            self.assertEqual(calls, [])
            lookup(db, 'Missing, Nowhere', lambda url: b'[]', sleeps.append)
            lookup(db, 'Missing, Nowhere', fetch, sleeps.append)
            self.assertEqual(calls, [])
            self.assertTrue(all(n >= 1 for n in sleeps))

    def test_11_poll_idempotent(self):
        from watch.pm.sources import poll_pm
        def fetch(url):
            return fixture('news.rss' if url.endswith('news.rss') else 'nominatim-calgary.json').encode()
        counts = []
        for _ in range(2):
            self.assertTrue(poll_pm(self.data, fetch, lambda n: None, NOW))
            with connect(self.data) as db:
                counts.append(tuple(db.execute('SELECT count(*) FROM ' + t).fetchone()[0]
                                    for t in ('pm_items', 'pm_events', 'pm_places')))
                self.assertEqual(counts[-1][0], len(rss_items()))
                self.assertEqual(db.execute('SELECT type FROM pm_items WHERE id=?', (CALGARY,)).fetchone()[0], 'itinerary')
                self.assertEqual(db.execute("SELECT type FROM pm_items WHERE id LIKE 'readouts/%' LIMIT 1").fetchone()[0], 'readout')
                self.assertEqual(db.execute('SELECT count(*) FROM pm_events WHERE item_id=?', (CALGARY,)).fetchone()[0], 4)
                self.assertTrue(json.loads(db.execute("SELECT value FROM meta WHERE key='source:pm'").fetchone()[0])['ok'])
        self.assertEqual(counts[0], counts[1])
        import gzip
        raw = list((self.data / 'raw' / 'pm').glob('*.gz'))
        self.assertTrue(raw)
        self.assertEqual(sum(len(gzip.open(p, 'rt').readlines()) for p in raw), 1)

    def test_12_newer_itinerary_replaces(self):
        from watch.pm.sources import save_item
        self.seed()
        with connect(self.data) as db, db:
            args = (db, BASE + 'media-advisories/2026/10/14/update-day-15', 'Thursday, October 15, 2026')
            save_item(*args, '2026-10-15T14:00:00Z', '<h2>National Capital Region, Canada</h2><p>noon Updated.</p>',
                      'rss', None, None, NOW)
            rows = db.execute("SELECT item_id,text FROM pm_events WHERE date='2026-10-15'").fetchall()
            self.assertEqual([tuple(r) for r in rows], [('media-advisories/2026/10/14/update-day-15', 'Updated.')])
            save_item(db, BASE + 'media-advisories/2026/10/14/day-15', 'Thursday, October 15, 2026',
                      '2026-10-14T21:00:00Z', '<h2>Calgary, Alberta</h2><p>9:00 a.m. Old.</p>',
                      'rss', None, None, NOW)
            self.assertEqual(db.execute("SELECT text FROM pm_events WHERE date='2026-10-15'").fetchone()[0], 'Updated.')

    def test_13_backfill_feed(self):
        from watch.pm.sources import backfill
        urls = {'https://www.pm.gc.ca' + urlsplit(u).path for u in fixture('cdx-readouts-2026-09.txt').splitlines()}
        self.assertEqual(len(urls), 12)
        calls, timeline = [], []
        def fetch(url):
            if 'web.archive.org' in url:
                return fixture('cdx-readouts-2026-09.txt').encode() if 'readouts/2026/' in url else b''
            timeline.append(('fetch', url))
            if '/media-advisories/' in url:
                raise HTTPError(url, 404, 'missing', None, None)
            calls.append(url)
            return fixture('readout-guyana.html').encode()
        def sleep(n):
            timeline.append(('sleep', n))
        now = datetime(2026, 9, 30, tzinfo=timezone.utc)
        backfill(self.data, fetch, sleep, now, since='2026-09-01')
        self.assertEqual(set(calls), urls)
        self.assertEqual(len(calls), 12)
        for i, (kind, value) in enumerate(timeline):
            if kind == 'fetch' and i:
                self.assertEqual(timeline[i-1][0], 'sleep')
                self.assertGreaterEqual(timeline[i-1][1], 1.0)
        with connect(self.data) as db:
            row = db.execute('SELECT * FROM pm_items LIMIT 1').fetchone()
            self.assertEqual(row['title'], 'Prime Minister Carney speaks with President of Guyana Dr. Mohamed Irfaan Ali')
            self.assertEqual(row['published_at'], '2026-10-14T23:18:00Z')
            self.assertIn('<p>Today,', row['body_html'])
            self.assertNotIn('Type keyword', row['text'])
        calls.clear()
        backfill(self.data, fetch, sleep, now, since='2026-09-01')
        self.assertEqual(calls, [])

    def test_14_today_and_feed(self):
        self.seed()
        server = self.server()
        status, today = self.get(server, '/api/pm/today')
        self.assertEqual(status, 200)
        self.assertEqual([d['date'] for d in today['days']], ['2026-10-15', '2026-10-16'])
        self.assertEqual(today['days'][0]['notes'], ['Private meetings'])
        self.assertEqual(today['now']['event']['local_time'], '09:15')
        self.assertEqual(today['now']['place']['id'], 'calgary-alberta')
        self.assertEqual(today['next']['local_time'], '12:30')
        self.assertEqual(today['fetched_at'], '2026-10-15T16:00:00Z')
        status, first = self.get(server, '/api/pm/feed?limit=2')
        self.assertEqual(status, 200)
        self.assertEqual(len(first['items']), 2)
        self.assertIsNotNone(first['next'])
        status, second = self.get(server, '/api/pm/feed?limit=2&before=' + quote(first['next'], safe=''))
        self.assertEqual(status, 200)
        self.assertTrue(second['items'])
        self.assertFalse({i['id'] for i in first['items']} & {i['id'] for i in second['items']})
        status, filtered = self.get(server, '/api/pm/feed?type=readout')
        self.assertEqual(len(filtered['items']), 3)
        self.assertEqual({i['type'] for i in filtered['items']}, {'readout'})

    def test_15_places_path_items(self):
        self.seed()
        server = self.server()
        status, places = self.get(server, '/api/pm/places?since=2026-10-14&until=2026-10-16')
        self.assertEqual(status, 200)
        self.assertEqual((places['places'][0]['visits'], places['places'][0]['days']), (6, 3))
        status, path = self.get(server, '/api/pm/path?since=2026-10-14&until=2026-10-16')
        self.assertEqual(status, 200)
        self.assertEqual(len(path['stops']), 1)
        self.assertEqual((path['stops'][0]['events'], path['stops'][0]['first_time']), (6, '09:15'))
        for query in ('since=2026-09-01&until=2026-10-03', 'since=bad&until=2026-10-15'):
            self.assertEqual(self.get(server, '/api/pm/path?' + query)[0], 400)
        self.assertEqual(self.get(server, '/api/pm/places?since=2026-02-30')[0], 400)
        status, item = self.get(server, '/api/pm/items/readouts/2026/10/14/item-0')
        self.assertEqual(status, 200)
        self.assertEqual(item['body'], '<p>Hello <em>Canada</em>.</p>')
        self.assertEqual(item['text'], 'Hello Canada.')
        self.assertEqual(item['events'], [])
        self.assertEqual(self.get(server, '/api/pm/items/missing/with/slashes')[0], 404)

    def test_16_export(self):
        from watch.opinion.export import export
        self.seed()
        server = self.server()
        def fetch(url):
            path = urlsplit(url).path
            if '/api/pm/' in path:
                status, body = self.get(server, path + ('?' + urlsplit(url).query if urlsplit(url).query else ''))
                self.assertEqual(status, 200)
            else:
                body = {'polls': [], 'next': None} if path.endswith('/list') else {'ridings': []} if path.endswith('/ridings') else {}
            return json.dumps(body).encode()
        out = self.data / 'snapshot'
        self.assertEqual(export('http://local', out, fetch), 8)
        self.assertEqual({p.name for p in (out / 'pm').iterdir()}, {'today.json', 'feed.json', 'places.json', 'path.json'})
        self.assertEqual((out / 'pm' / 'places.json').read_bytes(),
                         b'{"places":[{"id":"calgary-alberta","name":"Calgary, Alberta","country":"Canada","lat":51.0456064,"lon":-114.057541,"zone":"America/Edmonton","visits":4,"days":2,"first":"2026-10-14","last":"2026-10-15"}],"since":"2025-03-14","until":"2026-10-15"}')
        self.assertIsNone(json.loads((out / 'pm' / 'feed.json').read_bytes())['next'])
        with connect(self.data) as db, db:
            db.execute('DELETE FROM pm_events')
            db.execute('DELETE FROM pm_items')
            db.execute('DELETE FROM pm_places')
        self.assertEqual(export('http://local', out, fetch), 8)
        self.assertTrue((out / 'summary.json').exists())
        self.assertEqual(json.loads((out / 'pm' / 'today.json').read_bytes())['days'], [])
