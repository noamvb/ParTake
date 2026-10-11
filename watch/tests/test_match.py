import copy
import json
import subprocess
import sys
import tempfile
import unittest

from watch import store
from watch.tests.test_api import SEAM
from watch.tests.test_embed import closed_url, fake_server
from watch.tests.test_feed import follows, paragraph


def unit(x=1.0):
    return [x, (1 - x*x) ** .5] + [0.0] * 766


def fake_embed(texts):
    return [unit(.6 if text.startswith('six') else .5 if text.startswith('five') else 1.0)
            for text in texts]


def division(db, number, split=True):
    did = '45-1/%d' % number
    db.execute('INSERT INTO divisions(id,number,at,bill,description,result,yeas,nays,paired) VALUES (?,?,?,?,?,?,?,?,?)',
               (did, number, '2026-10-08T19:15:00Z', '45-1/C-37', 'Vote', 'agreed', 1, 1, 1))
    db.executemany('INSERT INTO ballots VALUES (?,?,?,?)',
                   [(did, '123447', 'Conservative', 'nay'),
                    (did, '2', 'Conservative' if split else 'Liberal', 'yea'),
                    (did, '3', 'Liberal', 'paired')])


class MatchTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.data = self.temp.name
        self.context = store.connect(self.data)
        self.db = self.context.__enter__()
        self.addCleanup(self.context.__exit__, None, None, None)

    def ids(self, fid):
        return {r[0] for r in self.db.execute('SELECT item_id FROM matches WHERE follow=?', (fid,))}

    def test_07_bill_tokens(self):
        from watch.match import match_rules
        follows(self.db)
        texts = ['C-37', 'c‑37', 'projet de loi C-37', 'C 37', 'C-370', 'BC-37', 'C-3']
        for i, text in enumerate(texts):
            paragraph(self.db, 'h%d' % i, text)
        match_rules(self.db)
        self.assertEqual(self.ids('f_jkl567'), {'h0', 'h1', 'h2', 'h3'})
        before = list(self.db.execute('SELECT * FROM matches'))
        match_rules(self.db)
        self.assertEqual(list(self.db.execute('SELECT * FROM matches')), before)

    def test_08_mp_first_intervention(self):
        from watch.match import sync
        follows(self.db)
        for position in (2, 0, 1):
            paragraph(self.db, 'h%d' % position, 'short', intervention='one', position=position, person_id='123447')
        sync(self.db, fake_embed)
        self.assertEqual(self.ids('f_mno234'), {'h0'})
        paragraph(self.db, 'h4', 'short', intervention='two', person_id='123447')
        sync(self.db, fake_embed)
        self.assertEqual(self.ids('f_mno234'), {'h0', 'h4'})
        # A lower position arriving late replaces the earlier first paragraph.
        paragraph(self.db, 'h5', 'short', intervention='two', position=-1, person_id='123447')
        sync(self.db, fake_embed)
        self.assertEqual(self.ids('f_mno234'), {'h0', 'h5'})

    def test_09_vote_rules(self):
        from watch.match import match_rules
        follows(self.db)
        f = copy.deepcopy(json.loads(SEAM)['follows'][5])
        f['id'], f['votes']['filter'] = 'f_all234', 'all'
        follows(self.db, [f])
        division(self.db, 1)
        division(self.db, 2, split=False)
        match_rules(self.db)
        self.assertEqual(self.ids('f_pqr567'), {'45-1/1'})
        self.assertEqual(self.ids('f_all234'), {'45-1/1', '45-1/2'})

    def test_10_topic_cosine_keywords_and_short(self):
        from watch.match import sync
        follows(self.db)
        paragraph(self.db, 'h6', 'six two three four five six seven eight')
        paragraph(self.db, 'h5', 'five two three four five six seven eight')
        paragraph(self.db, 'h7', 'one two three four five six seven')
        paragraph(self.db, 'h8', 'short', text_fr='cmhc', lang='fr')
        calls = []
        def embedder(texts):
            calls.extend(texts)
            return fake_embed(texts)
        sync(self.db, embedder)
        self.assertEqual(self.ids('f_ghi234'), {'h6', 'h8'})
        scores = dict(self.db.execute("SELECT item_id,score FROM matches WHERE follow='f_ghi234'"))
        self.assertAlmostEqual(scores['h6'], .6, delta=.002)
        self.assertEqual(scores['h8'], 1.0)
        self.assertNotIn('one two three four five six seven', calls)
        self.assertEqual(self.db.execute('SELECT count(*) FROM follow_vectors').fetchone()[0], 2)
        calls.clear()
        sync(self.db, embedder)
        self.assertEqual(calls, [])

    def test_11_newest_batch_backfill(self):
        from watch.match import sync
        for i in range(70):
            paragraph(self.db, 'h%d' % i, at='2026-10-%02dT00:00:00Z' % (1 + i//3))
        sync(self.db, fake_embed, batch=32, max_batches=1)
        self.assertEqual({r[0] for r in self.db.execute('SELECT paragraph FROM vectors')},
                         {'h%d' % i for i in range(38, 70)})
        self.assertEqual(json.loads(self.db.execute("SELECT value FROM meta WHERE key='backfill'").fetchone()[0]),
                         {'done': 32, 'total': 70})

    def test_12_embed_failure_rules_and_worker(self):
        from watch.match import sync
        from watch.embed import EmbedError
        from watch.worker import main
        follows(self.db)
        paragraph(self.db, 'h1', 'C-37 two three four five six seven eight', person_id='123447')
        division(self.db, 1)
        def broken(_texts):
            raise EmbedError('offline')
        result = sync(self.db, broken)
        self.assertEqual(result['embed_error'], 'offline')
        self.assertEqual(self.ids('f_jkl567'), {'h1', '45-1/1'})
        self.assertEqual(self.ids('f_mno234'), {'h1', '45-1/1'})
        self.assertEqual(self.ids('f_pqr567'), {'45-1/1'})
        self.assertEqual(self.db.execute('SELECT count(*) FROM vectors').fetchone()[0], 0)
        self.assertEqual(main(['--data', self.data, '--ollama', closed_url()]), 1)
        record = json.loads(self.db.execute("SELECT value FROM meta WHERE key='source:embed'").fetchone()[0])
        self.assertFalse(record['ok'])
        self.assertTrue(record['error'])
        # Once phrases exist, a later failed paragraph batch must preserve
        # the earlier batch, including after reopening the database.
        sync(self.db, fake_embed)
        paragraph(self.db, 'h2')
        paragraph(self.db, 'h3')
        calls = []
        def partial(texts):
            calls.append(texts)
            if len(calls) == 2:
                raise EmbedError('second batch offline')
            return fake_embed(texts)
        result = sync(self.db, partial, batch=1)
        self.assertEqual(result['embedded'], 1)
        self.assertEqual(result['embed_error'], 'second batch offline')
        with store.connect(self.data) as reopened:
            self.assertEqual({r[0] for r in reopened.execute('SELECT paragraph FROM vectors')}, {'h1', 'h3'})

    def test_13_edited_follow_recomputes(self):
        from watch.match import sync
        follows(self.db)
        paragraph(self.db, 'h6', 'six C-37 three four five six seven eight')
        sync(self.db, fake_embed)
        self.assertEqual(self.ids('f_ghi234'), {'h6'})
        others = [tuple(r) for r in self.db.execute("SELECT * FROM matches WHERE follow!='f_ghi234'")]
        f = store.list_follows(self.db)['follows'][2]
        f['topic']['threshold'] = .65
        self.db.execute('UPDATE follows SET body=? WHERE id=?', (json.dumps(f), f['id']))
        def cached_only(_texts):
            self.fail('unchanged phrases must reuse stored vectors')
        sync(self.db, cached_only)
        self.assertEqual(self.ids('f_ghi234'), set())
        self.assertEqual([tuple(r) for r in self.db.execute("SELECT * FROM matches WHERE follow!='f_ghi234'")], others)

    def test_14_incremental_invariant(self):
        from watch.match import sync
        final = copy.deepcopy(json.loads(SEAM)['follows'])
        final[2]['topic']['threshold'] = .65
        def add(db, i):
            paragraph(db, 'h%d' % i, ('six' if i == 0 else 'one') + ' C-37 three four five six seven eight',
                      person_id='123447', intervention='same', position=2-i)
            division(db, i+1, split=(i != 0))
        with tempfile.TemporaryDirectory() as data, store.connect(data) as once:
            follows(once, final)
            for i in range(3):
                add(once, i)
            sync(once, fake_embed)
            expected = [tuple(r) for r in once.execute('SELECT * FROM matches ORDER BY follow,item_kind,item_id')]
        initial = copy.deepcopy(json.loads(SEAM)['follows'])
        follows(self.db, [f for f in initial if f['kind'] != 'mp'])
        for i in range(3):
            add(self.db, i)
            if i == 1:
                follows(self.db, [initial[4]])
            if i == 2:
                self.db.execute('UPDATE follows SET body=? WHERE id=?', (json.dumps(final[2]), final[2]['id']))
            sync(self.db, fake_embed)
        self.assertEqual([tuple(r) for r in self.db.execute('SELECT * FROM matches ORDER BY follow,item_kind,item_id')], expected)

    def test_16_worker_cli_happy(self):
        from watch.embed import unpack
        _, url = fake_server(self)
        paragraph(self.db, 'h1')
        self.db.commit()
        result = subprocess.run([sys.executable, '-m', 'watch.worker', '--data', self.data, '--ollama', url],
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        blob = self.db.execute('SELECT vec FROM vectors').fetchone()[0]
        self.assertEqual(len(unpack(blob)), 768)
        record = json.loads(self.db.execute("SELECT value FROM meta WHERE key='source:embed'").fetchone()[0])
        self.assertTrue(record['ok'])
        self.assertIsNone(record['error'])
