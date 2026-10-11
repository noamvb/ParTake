from datetime import datetime, timezone
import http.client
import json
import tempfile
import threading
import unittest

from watch import store
from watch.tests.test_api import SEAM
from watch.tests.test_embed import closed_url


TEXT_EN = ('She said: Madam Speaker, waachiyeh, meesuuyeh, kwe, ulaakut, tansi and hello. '
           'I rise today as a proud eeyou iskwew from the community of Waswanipi, and also '
           'as the Minister of Indigenous Services, to speak to Bill C-37, the first nations clean water act.')
TEXT_FR = ("Comme vous le savez, le CRTC est un tribunal quasi judiciaire indépendant qui réglemente "
           "le secteur canadien des communications dans l'intérêt public. Nous tenons des consultations "
           "publiques sur des questions de télécommunications et de radiodiffusion, et nous prenons des "
           "décisions fondées sur le dossier public.")
DESCRIPTION = ('3rd reading and adoption of Bill C-37, An Act respecting water, source water, drinking '
               'water, wastewater and related infrastructure on First Nation lands')
# Independent fixed contract: the fixture is deliberately not built by feed helpers.
FEED_SEAM = r'''{"items": [
 {"id":"m_b_2","kind":"bill_stage","at":"2026-10-09T17:20:48Z","follows":[{"id":"f_jkl567","score":1.0}],"source":"legisinfo","superseded":false,"title":"C-37: Second reading (House of Commons)","text":"First Nations Clean Water Act","lang":"en","speaker":null,"video":null,"links":{"hansard":null,"legisinfo":"https://www.parl.ca/legisinfo/en/bill/45-1/c-37","division":null},"division":null,"bill_stage":{"bill":"45-1/C-37","number":"C-37","stage":"Second reading","chamber":"house","at":"2026-10-09T17:20:48Z"}},
 {"id":"m_s_h9484631","kind":"speech","at":"2026-10-09T14:00:00Z","follows":[{"id":"f_ghi234","score":0.712},{"id":"f_jkl567","score":1.0}],"source":"hansard","superseded":false,"title":"Government Orders - First Nations Clean Water Act","text":"She said: Madam Speaker, waachiyeh, meesuuyeh, kwe, ulaakut, tansi and hello. I rise today as a proud eeyou iskwew from the community of Waswanipi, and also as the Minister of Indigenous Services, to speak to Bill C-37, the first nations clean water act.","lang":"en","speaker":{"person_id":"122492","name":"Mandy Gull-Masty","party":"Liberal","confidence":1.0,"from":"hansard"},"video":null,"links":{"hansard":"https://www.ourcommons.ca/DocumentViewer/en/45-1/house/sitting-149/hansard#Para9484631","legisinfo":null,"division":null},"division":null,"bill_stage":null},
 {"id":"m_d_45-1-7","kind":"division","at":"2026-10-08T19:15:00Z","follows":[{"id":"f_jkl567","score":1.0},{"id":"f_mno234","score":1.0},{"id":"f_pqr567","score":1.0}],"source":"votes","superseded":false,"title":"Vote 7: Negatived","text":"3rd reading and adoption of Bill C-37, An Act respecting water, source water, drinking water, wastewater and related infrastructure on First Nation lands","lang":"en","speaker":null,"video":null,"links":{"hansard":null,"legisinfo":"https://www.parl.ca/legisinfo/en/bill/45-1/c-37","division":"https://www.ourcommons.ca/Members/en/votes/45/1/7"},"division":{"id":"45-1/7","number":7,"bill":"45-1/C-37","description":"3rd reading and adoption of Bill C-37, An Act respecting water, source water, drinking water, wastewater and related infrastructure on First Nation lands","result":"negatived","yeas":1,"nays":2,"paired":0,"parties":[{"party":"Conservative","yea":1,"nay":1,"split":true},{"party":"Liberal","yea":0,"nay":1,"split":false}],"mps":[{"person_id":"123447","vote":"nay"}]},"bill_stage":null},
 {"id":"m_s_e9484374","kind":"speech","at":"2026-10-06T15:05:00Z","follows":[{"id":"f_ghi234","score":0.613}],"source":"evidence","superseded":false,"title":"INDU, meeting 50","text":"Comme vous le savez, le CRTC est un tribunal quasi judiciaire indépendant qui réglemente le secteur canadien des communications dans l'intérêt public. Nous tenons des consultations publiques sur des questions de télécommunications et de radiodiffusion, et nous prenons des décisions fondées sur le dossier public.","lang":"fr","speaker":{"person_id":null,"name":"Sheehan Carter","party":null,"confidence":1.0,"from":"evidence"},"video":null,"links":{"hansard":"https://www.ourcommons.ca/DocumentViewer/en/45-1/INDU/meeting-50/evidence#Para9484374","legisinfo":null,"division":null},"division":null,"bill_stage":null}
],"next":null}'''


def follows(db, items=None):
    for f in items if items is not None else json.loads(SEAM)['follows']:
        db.execute('INSERT INTO follows(id,created_at,body) VALUES (?,?,?)',
                   (f['id'], f['created_at'], json.dumps(f)))


def paragraph(db, pid, text='one two three four five six seven eight', **kwargs):
    row = dict(id=pid, document='hansard/45-1/149', intervention=pid, position=0,
               at='2026-10-09T14:00:00Z', title='Title', lang='en', text_en=text,
               text_fr='', speaker=None, person_id=None, source='hansard')
    row.update(kwargs)
    db.execute('INSERT INTO paragraphs(%s) VALUES (%s)' %
               (','.join(row), ','.join('?' for _ in row)), tuple(row.values()))


def seam(db):
    from watch.match import match_rules
    follows(db)
    db.executemany('INSERT INTO members(person_id,name,party) VALUES (?,?,?)',
                   [('122492', 'Mandy Gull-Masty', 'Liberal'), ('123447', 'Billy Morin', 'Conservative'),
                    ('2', 'Other', 'Conservative'), ('3', 'Other', 'Liberal')])
    db.execute("INSERT INTO bills(id,number,title) VALUES ('45-1/C-37','C-37','First Nations Clean Water Act')")
    db.execute("INSERT INTO bill_stages VALUES (2,'45-1/C-37','Second reading','house','2026-10-09T17:20:48Z')")
    for doc, source, committee, number, url in [
        ('hansard/45-1/149', 'hansard', None, 149, 'https://www.ourcommons.ca/DocumentViewer/en/45-1/house/sitting-149/hansard'),
        ('evidence/45-1/INDU/50', 'evidence', 'INDU', 50, 'https://www.ourcommons.ca/DocumentViewer/en/45-1/INDU/meeting-50/evidence')]:
        db.execute('INSERT INTO documents VALUES (?,?,?,?,?,?,?,?)',
                   (doc, source, '45-1', number, committee, '2026-10-09', url, '2026-10-09T00:00:00Z'))
    paragraph(db, 'h9484631', TEXT_EN, speaker='Hon. Mandy Gull-Masty (Minister of Indigenous Services, Lib.)',
              person_id='122492', title='Government Orders - First Nations Clean Water Act')
    paragraph(db, 'e9484374', 'Short translation', text_fr=TEXT_FR, lang='fr', source='evidence',
              document='evidence/45-1/INDU/50', at='2026-10-06T15:05:00Z', title='INDU, meeting 50',
              speaker='Sheehan Carter (Director General, Strategic Policy, Consumer, Analytics and Strategy, Canadian Radio-television and Telecommunications Commission)')
    db.execute('INSERT INTO divisions(id,number,at,bill,description,result,yeas,nays,paired) VALUES (?,?,?,?,?,?,?,?,?)',
               ('45-1/7', 7, '2026-10-08T19:15:00Z', '45-1/C-37', DESCRIPTION, 'negatived', 1, 2, 0))
    db.executemany('INSERT INTO ballots VALUES (?,?,?,?)', [('45-1/7', '123447', 'Conservative', 'nay'),
                   ('45-1/7', '2', 'Conservative', 'yea'), ('45-1/7', '3', 'Liberal', 'nay')])
    match_rules(db)
    db.executemany('INSERT INTO matches VALUES (?,?,?,?,?)',
                   [('f_ghi234', 'paragraph', 'h9484631', .7123, '2026-10-09T14:00:00Z'),
                    ('f_ghi234', 'paragraph', 'e9484374', .6128, '2026-10-06T15:05:00Z')])
    db.commit()


class FeedTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.data = self.temp.name
        self.context = store.connect(self.data)
        self.db = self.context.__enter__()
        self.addCleanup(self.context.__exit__, None, None, None)

    def http(self, path):
        if not hasattr(self, 'server'):
            from watch.api import make_server
            self.server = make_server(self.data, '127.0.0.1', 0, ollama=closed_url())
            thread = threading.Thread(target=self.server.serve_forever, daemon=True)
            thread.start()
            def close():
                self.server.shutdown()
                self.server.server_close()
                thread.join()
            self.addCleanup(close)
        conn = http.client.HTTPConnection('127.0.0.1', self.server.server_port, timeout=3)
        conn.request('GET', path)
        response = conn.getresponse()
        result = response.status, json.loads(response.read())
        conn.close()
        return result

    def test_03_feed_seam(self):
        from watch.feed import feed
        seam(self.db)
        self.assertEqual(feed(self.db), json.loads(FEED_SEAM))

    def test_04_http_seam_and_filters(self):
        seam(self.db)
        self.assertEqual(self.http('/api/feed'), (200, json.loads(FEED_SEAM)))
        self.assertEqual([x['id'] for x in self.http('/api/feed?kind=division')[1]['items']], ['m_d_45-1-7'])
        items = self.http('/api/feed?follow=f_ghi234')[1]['items']
        self.assertEqual(items, [x for x in json.loads(FEED_SEAM)['items'] if x['kind'] == 'speech'])

    def test_05_paging_and_bad_parameters(self):
        from watch.feed import feed
        seam(self.db)
        paragraph(self.db, 'h5', 'C-37')
        from watch.match import match_rules
        match_rules(self.db)
        self.db.commit()
        all_items = feed(self.db)['items']
        pages = []
        cursor = None
        sizes = []
        while True:
            page = feed(self.db, limit=2, before=cursor)
            pages.extend(page['items'])
            sizes.append(len(page['items']))
            cursor = page['next']
            if cursor is None:
                break
        self.assertEqual(sizes, [2, 2, 1])
        self.assertEqual(pages, all_items)
        self.assertEqual(len({x['id'] for x in pages}), 5)
        for query in ('limit=0', 'limit=201', 'kind=nope', 'before=garbage', 'follow=f_zzzzzz'):
            self.assertEqual(self.http('/api/feed?' + query)[0], 400)

    def test_06_removed_follow_rows_retained(self):
        from watch.feed import feed
        seam(self.db)
        self.assertEqual(len(feed(self.db)['items']), 4)
        count = self.db.execute('SELECT count(*) FROM matches').fetchone()[0]
        current = store.list_follows(self.db)
        store.replace_follows(self.data, {'version': current['version'], 'follows': [
            f for f in current['follows'] if f['id'] != 'f_ghi234']},
            lambda: datetime.now(timezone.utc), lambda: 'unused')
        items = feed(self.db)['items']
        self.assertEqual(len(items), 3)
        speech = next(x for x in items if x['kind'] == 'speech')
        self.assertEqual(speech['follows'], [{'id': 'f_jkl567', 'score': 1.0}])
        self.assertEqual(self.db.execute('SELECT count(*) FROM matches').fetchone()[0], count)

    def test_15_health_backfill(self):
        self.assertIsNone(self.http('/api/health')[1]['backfill'])
        store.set_meta(self.db, 'backfill', json.dumps({'done': 32, 'total': 70}))
        self.db.commit()
        health = self.http('/api/health')[1]
        self.assertEqual(health['backfill'], {'done': 32, 'total': 70})
        self.assertEqual(health['embed'], {'model': 'paraphrase-multilingual', 'loaded': False})
