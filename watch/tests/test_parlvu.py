from contextlib import redirect_stderr
from datetime import datetime, timezone
import gzip
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from watch.store import connect, set_meta


NOW = datetime(2026, 10, 11, 16, tzinfo=timezone.utc)
BASE = 'https://parlvu.parl.gc.ca'
UPCOMING = BASE + '/Harmony/en/api/Data/GetUpcomingEvents?lastModified='
PAGE = BASE + '/Harmony/en/PowerBrowser/PowerBrowserV2/-1/-1/'
SD_URL = ('https://parlvuvod01.azureedge.net/pvvodhoc-en/_definst_/mp4:azrhoc02/archives/'
          'PV750/2026/2026-10-09/45735_HoC%20Sitting%20No.%20149_10-00-34_VL.mp4/'
          'playlist.m3u8?audioindex=1&wowzalanguage=eng')


def fixture(name):
    path = Path(__file__).parent / 'fixtures' / name
    return gzip.decompress(path.read_bytes()) if name.endswith('.gz') else path.read_bytes()


def listing_url(day):
    return BASE + ('/Harmony/en/api/Data/GetListViewData?categoryId=-1&fromDate='
                   + day + '&endDate=' + day + '&searchTime=&searchForward=true&order=asc')


def null_page():
    html = fixture('parlvu-event-45735.html.gz').decode()
    start = html.index('\tccItems:') + len('\tccItems:')
    _, length = json.JSONDecoder().raw_decode(html[start:])
    return (html[:start] + 'null' + html[start + length:]).encode()


class ParlvuTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.data = Path(self.temp.name)
        self.calls, self.sleeps = [], []

    def meta(self, key):
        with connect(self.data) as db:
            row = db.execute('SELECT value FROM meta WHERE key=?', (key,)).fetchone()
            return row[0] if row else None

    def setup_poll(self, page=None, upcoming=None):
        with connect(self.data) as db, db:
            set_meta(db, 'parlvu:through', '2026-10-08')
        mapping = {listing_url(day): b'{"Weeks":[]}' for day in ('20261010', '20261011')}
        mapping[listing_url('20261009')] = fixture('parlvu-listing-20261009.json')
        mapping[UPCOMING] = upcoming if upcoming is not None else fixture('parlvu-upcoming.json')
        mapping[PAGE + '45735'] = page if page is not None else fixture('parlvu-event-45735.html.gz')
        return mapping

    def fetcher(self, mapping):
        def fetch(url):
            self.calls.append(url)
            body = mapping[url]
            if isinstance(body, Exception):
                raise body
            return body
        return fetch

    def poll(self, mapping, **kwargs):
        from watch.parlvu import poll_parlvu
        return poll_parlvu(self.data, self.fetcher(mapping), self.sleeps.append, NOW, **kwargs)

    def test_01_ottawa_utc(self):
        from watch.parlvu import ottawa_utc
        cases = [('2026-10-09T10:01:04', '2026-10-09T14:01:04Z'),
                 ('2026-10-09T10:00:40.19', '2026-10-09T14:00:40.190Z'),
                 ('2026-10-09T10:00:40.1', '2026-10-09T14:00:40.100Z'),
                 ('2026-10-09T10:00:40.1999999', '2026-10-09T14:00:40.199Z'),
                 (None, None), ('2026-01-15T09:00:00', '2026-01-15T14:00:00Z')]
        for value, expected in cases:
            with self.subTest(value=value):
                self.assertEqual(ottawa_utc(value), expected)

    def test_02_listing_event(self):
        from watch.parlvu import event_row, parse_listing
        rows = [event_row(row, NOW) for row in parse_listing(fixture('parlvu-listing-20261009.json'))]
        self.assertEqual([row for row in rows if row], [dict(
            id='45735', title='House of Commons, sitting 149', kind='house', committee=None,
            number=149, document='hansard/45-1/149', scheduled_start='2026-10-09T14:00:00Z',
            actual_start='2026-10-09T14:01:04Z', actual_end='2026-10-09T18:31:27Z',
            status=-1, has_archive=0, recording_start=None, preroll_s=None, stream_url=None,
            captions='none', updated_at='2026-10-11T16:00:00Z')])
        sample = parse_listing(fixture('parlvu-listing-20261009.json'))[1]
        self.assertEqual(event_row(dict(sample, HasArchiveStream=True), NOW)['has_archive'], 1)
        for title in ('TRAN Meeting No. 30-16', 'CC39 Meeting No. 1', 'HoC Sitting No. 149 extra'):
            self.assertIsNone(event_row(dict(sample, Title=title), NOW))

    def test_03_week(self):
        from watch.parlvu import event_row, parse_listing
        rows = [event_row(row, NOW) for row in parse_listing(fixture('parlvu-listing-20261005-20261011.json').decode())]
        kept = [row for row in rows if row]
        self.assertEqual([row['number'] for row in kept if row['kind'] == 'house'], [145, 146, 147, 148])
        self.assertTrue(any(row['kind'] == 'committee' for row in kept))
        for row in kept:
            if row['kind'] == 'committee':
                self.assertRegex(row['document'], r'^evidence/45-1/[A-Z]{3,5}/\d+$')

    def test_04_upcoming(self):
        from watch.parlvu import event_row, parse_upcoming
        parsed = parse_upcoming(fixture('parlvu-upcoming.json'))
        self.assertEqual(len(parsed), 11)
        rows = {r['id']: r for row in parsed if (r := event_row(row, NOW))}
        self.assertEqual(tuple(rows['45873'][key] for key in ('kind', 'number', 'scheduled_start', 'status')),
                         ('house', 150, '2026-10-19T15:00:00Z', 0))
        self.assertEqual(rows['44792']['status'], 2)
        self.assertEqual(rows['44792']['document'], 'evidence/45-1/TRAN/30')
        self.assertEqual(parse_upcoming(fixture('parlvu-upcoming.json').decode()), parsed)

    def test_05_event_page(self):
        from watch.parlvu import parse_event_page
        page = parse_event_page(fixture('parlvu-event-45735.html.gz'))
        self.assertEqual(page['recording_start'], '2026-10-09T14:01:04Z')
        self.assertEqual(page['preroll_s'], 30.0)
        self.assertTrue(page['stream_url'].startswith('https://'))
        self.assertEqual(page['stream_url'], SD_URL)

    def test_06_caption_fixtures(self):
        from watch.parlvu import caption_rows, parse_event_page
        for event in ('45735', '45822'):
            page = parse_event_page(fixture('parlvu-event-' + event + '.html.gz'))
            expected = json.loads(fixture('captions-' + event + '-en.json.gz'))
            actual = caption_rows(event, page)
            self.assertEqual(len(actual), len(expected))
            for seq, (row, wanted) in enumerate(zip(actual, expected)):
                self.assertEqual(row, wanted, f"{event}: first differing row {seq}")

    def test_07_null_captions(self):
        from watch.parlvu import caption_rows, parse_event_page
        page = parse_event_page(null_page().decode())
        self.assertIsNone(page['captions'])
        self.assertEqual(caption_rows('45735', page), [])

    def test_08_ambiguous_marker(self):
        from watch.parlvu import parse_event_page
        with self.assertRaises(ValueError):
            parse_event_page(fixture('parlvu-event-45735.html.gz').decode() + 'var availableStreams = []')

    def test_09_poll(self):
        self.assertTrue(self.poll(self.setup_poll(), max_days=60))
        self.assertEqual(self.calls, [listing_url(day) for day in ('20261009', '20261010', '20261011', '20261010', '20261011')]
                         + [UPCOMING, PAGE + '45735'])
        self.assertEqual(self.meta('parlvu:through'), '2026-10-10')
        with connect(self.data) as db:
            row = db.execute("SELECT * FROM events WHERE id='45735'").fetchone()
            self.assertEqual(row['captions'], 'archive')
            self.assertEqual(row['recording_start'], '2026-10-09T14:01:04Z')
            self.assertEqual(db.execute("SELECT count(*) FROM events WHERE id='45873'").fetchone()[0], 1)
            self.assertEqual(db.execute("SELECT count(*) FROM captions WHERE event='45735' AND source='archive'").fetchone()[0], 8436)
        self.assertTrue(json.loads(self.meta('source:parlvu'))['ok'])
        self.assertEqual(self.sleeps, [1.0] * (len(self.calls) - 1))
        for key in ('listing/20261009', 'upcoming', 'event/45735'):
            self.assertIsNotNone(self.meta('raw:parlvu/' + key))
        self.assertTrue(list((self.data / 'raw' / 'parlvu_pages').glob('*.jsonl.gz')))

    def test_10_rerun_preserves_archive(self):
        mapping = self.setup_poll()
        self.assertTrue(self.poll(mapping))
        # Re-fetch the same event through yesterday's refresh.
        mapping[listing_url('20261010')] = mapping[listing_url('20261009')]
        self.calls.clear()
        self.assertTrue(self.poll(mapping))
        self.assertNotIn(PAGE + '45735', self.calls)
        with connect(self.data) as db:
            row = db.execute("SELECT recording_start,preroll_s,stream_url,captions FROM events WHERE id='45735'").fetchone()
            self.assertEqual(tuple(row), ('2026-10-09T14:01:04Z', 30.0, SD_URL, 'archive'))
            self.assertEqual(db.execute('SELECT count(*) FROM captions').fetchone()[0], 8436)

    def test_11_no_caption_retry_limit(self):
        mapping = self.setup_poll(page=null_page())
        for attempt in range(1, 4):
            self.assertTrue(self.poll(mapping))
            self.assertEqual(self.meta('parlvu:nocc:45735'), str(attempt))
        self.assertEqual(self.calls.count(PAGE + '45735'), 3)
        self.calls.clear()
        self.assertTrue(self.poll(mapping))
        self.assertNotIn(PAGE + '45735', self.calls)
        with connect(self.data) as db:
            self.assertEqual(db.execute("SELECT captions FROM events WHERE id='45735'").fetchone()[0], 'none')

    def test_12_page_failure_continues(self):
        from watch.parlvu import event_row, parse_listing
        mapping = self.setup_poll(page=RuntimeError('broken event page'), upcoming=b'{"ContentEntityDatas":[]}')
        other = dict(parse_listing(mapping[listing_url('20261009')])[1], Id=45822,
                     Title='INDU Meeting No. 50', ScheduledStart='2026-10-08T10:00:00')
        row = event_row(other, NOW)
        with connect(self.data) as db, db:
            db.execute('INSERT INTO events VALUES (' + ','.join(':' + key for key in row) + ')', row)
        mapping[PAGE + '45822'] = fixture('parlvu-event-45822.html.gz')
        self.assertFalse(self.poll(mapping))
        self.assertEqual(self.calls[-2:], [PAGE + '45735', PAGE + '45822'])
        health = json.loads(self.meta('source:parlvu'))
        self.assertFalse(health['ok'])
        self.assertIn('broken event page', health['error'])
        with connect(self.data) as db:
            self.assertEqual(db.execute("SELECT captions FROM events WHERE id='45822'").fetchone()[0], 'archive')
            self.assertEqual(db.execute("SELECT count(*) FROM captions WHERE event='45822'").fetchone()[0], 1108)
        # Parse failures also allow the next page to load.
        mapping[PAGE + '45735'] = b'bad page'
        with connect(self.data) as db, db:
            db.execute("UPDATE events SET captions='live' WHERE id='45822'")
        self.calls.clear()
        self.assertFalse(self.poll(mapping))
        self.assertEqual(self.calls[-2:], [PAGE + '45735', PAGE + '45822'])
        self.assertIn('marker', json.loads(self.meta('source:parlvu'))['error'])

    def test_13_cli(self):
        from watch.poll import main
        with patch('watch.parlvu.poll_parlvu', return_value=True) as poll, redirect_stderr(io.StringIO()):
            self.assertEqual(main(['--sources', 'parlvu', '--data', str(self.data)]), 0)
        poll.assert_called_once()
        self.assertEqual(poll.call_args.args[0], str(self.data))
        with redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as error:
            main(['--sources', 'nope', '--data', str(self.data)])
        self.assertEqual(error.exception.code, 2)

    def test_14_page_validation(self):
        from watch.parlvu import parse_event_page
        html = fixture('parlvu-event-45735.html.gz').decode()
        for marker in ('var availableStreams = ', '\tEventInfo:', '\tccItems:'):
            for broken in (html.replace(marker, 'missing:'), html + marker + '{}', html.replace(marker, marker + '!')):
                with self.subTest(marker=marker), self.assertRaises(ValueError):
                    parse_event_page(broken)
        minimal = ('var availableStreams = [];\n\tEventInfo:{"timeTags":{"STARTTIME":{"timestamp":"2026-10-09T10:01:04"}}},'
                   '\n\tccItems:{"en":[{"Begin":"2026-10-09T10:01:04","End":"2026-10-09T10:01:05",'
                   '"Content":"quoted \\\" } ] text"}]}')
        page = parse_event_page(minimal)
        self.assertIsNone(page['stream_url'])
        self.assertIsNone(page['preroll_s'])
        self.assertEqual(page['captions']['en'][0]['Content'], 'quoted " } ] text')

    def test_15_caption_filtering(self):
        from watch.parlvu import caption_rows
        page = {'captions': {'en': [dict(Begin='2026-01-15T09:00:00', End='2026-01-15T09:00:01', Content='  '),
                                    dict(Begin='2026-01-15T09:00:01', End='2026-01-15T09:00:02.9999', Content=' hi ')]}}
        self.assertEqual(caption_rows('1', page), [dict(event='1', lang='en', source='archive', seq=0,
                                                       begin='2026-01-15T14:00:01.000Z', end='2026-01-15T14:00:02.999Z', text='hi')])
        self.assertEqual(caption_rows('1', page, 'fr'), [])

    def test_16_cursor_limits_and_live(self):
        from watch.parlvu import event_row, parse_listing
        mapping = {listing_url(day): b'{"Weeks":[]}' for day in ('20250526', '20250527', '20261010', '20261011')}
        mapping[UPCOMING] = b'{"ContentEntityDatas":[]}'
        self.assertTrue(self.poll(mapping, max_days=2, max_pages=0))
        self.assertEqual(self.calls, [listing_url(day) for day in ('20250526', '20250527', '20261010', '20261011')] + [UPCOMING])
        self.assertEqual(self.meta('parlvu:through'), '2025-05-27')
        mapping = self.setup_poll()
        row = event_row(parse_listing(mapping[listing_url('20261009')])[1], NOW)
        row['captions'] = 'live'
        with connect(self.data) as db, db:
            db.execute('INSERT INTO events VALUES (' + ','.join(':' + key for key in row) + ')', row)
        self.assertTrue(self.poll(mapping, max_pages=0))
        self.assertNotIn(PAGE + '45735', self.calls)
        with connect(self.data) as db, db:
            db.execute("INSERT INTO captions VALUES ('45735','en','archive',99999,'a','b','stale')")
            db.execute("INSERT INTO captions VALUES ('45735','en','live',0,'a','b','live')")
        self.assertTrue(self.poll(mapping, max_pages=1))
        with connect(self.data) as db:
            self.assertEqual(db.execute("SELECT captions FROM events WHERE id='45735'").fetchone()[0], 'archive')
            self.assertEqual(db.execute("SELECT count(*) FROM captions WHERE source='archive'").fetchone()[0], 8436)
            self.assertEqual(db.execute("SELECT text FROM captions WHERE source='live'").fetchone()[0], 'live')

    def test_17_listing_failure(self):
        mapping = self.setup_poll()
        mapping[listing_url('20261010')] = RuntimeError('listing failed')
        self.assertFalse(self.poll(mapping))
        self.assertEqual(self.meta('parlvu:through'), '2026-10-09')
        self.assertEqual(json.loads(self.meta('source:parlvu'))['error'], 'listing failed')
