from datetime import datetime, timezone
import json
import subprocess
import sys
import tempfile
import unittest

from watch import store
from watch.tests.test_feed import follows, paragraph
from watch.tests.test_api import SEAM

NOW = datetime(2026, 10, 12, 15, tzinfo=timezone.utc)


def digest_seed(db):
    follows(db, json.loads(SEAM)['follows'][2:4])
    for pid, at in [('early', '2026-10-09T14:00:00Z'), ('late', '2026-10-10T03:30:00Z'), ('next', '2026-10-10T04:30:00Z')]:
        paragraph(db, pid, at=at)
        db.execute('INSERT INTO matches VALUES (?,?,?,?,?)', ('f_ghi234', 'paragraph', pid, .7123, at))
    db.execute("INSERT INTO matches VALUES ('f_jkl567','paragraph','early',1,'2026-10-09T14:00:00Z')")
    db.commit()


class DigestTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.data = self.temp.name

    def test_evening_sections(self):
        from watch.digest import build
        from watch.feed import feed
        with store.connect(self.data) as db:
            digest_seed(db)
            body = build(db, '2026-10-09', 'evening', NOW)
            self.assertEqual(body['id'], 'd_2026-10-09_evening')
            self.assertIsNone(body['replaces'])
            self.assertEqual([s['follow'] for s in body['sections']], [{'id': 'f_ghi234', 'label': 'Housing affordability'}, {'id': 'f_jkl567', 'label': 'C-37'}])
            self.assertEqual([i['id'] for i in body['sections'][0]['items']], ['m_s_early', 'm_s_late'])
            self.assertEqual(body['sections'][1]['items'], [body['sections'][0]['items'][0]])
            self.assertEqual(body['sections'][0]['items'][0], feed(db)['items'][-1])
            self.assertEqual(len({i['id'] for s in body['sections'] for i in s['items']}), 2)

    def test_empty_morning_replacement_superseded(self):
        from watch.digest import build
        with store.connect(self.data) as db:
            self.assertIsNone(build(db, '2026-10-09', 'evening', NOW))
            digest_seed(db)
            self.assertIsNone(build(db, '2026-10-09', 'morning', NOW))
            self.assertEqual(db.execute('SELECT count(*) FROM digests').fetchone()[0], 0)
            evening = build(db, '2026-10-09', 'evening', NOW)
            db.execute("UPDATE paragraphs SET source='captions',superseded_by='hansard/45-1/149' WHERE id='late'")
            db.execute("INSERT INTO documents VALUES ('hansard/45-1/149','hansard','45-1',149,NULL,'2026-10-09','url','now')")
            body = build(db, '2026-10-09', 'morning', NOW)
            self.assertEqual(body['replaces'], evening['id'])
            self.assertEqual([i['id'] for i in body['sections'][0]['items']], ['m_s_early'])
            self.assertEqual(len(evening['sections'][0]['items']), 2)
            db.execute("UPDATE paragraphs SET superseded_by='doc'")
            self.assertIsNone(build(db, '2026-10-09', 'evening', NOW))

    def test_cli_dates(self):
        with store.connect(self.data) as db:
            digest_seed(db)
            db.execute("INSERT INTO documents VALUES ('hansard/45-1/149','hansard','45-1',149,NULL,'2026-10-09','url','now')")
            db.commit()
        base = [sys.executable, '-m', 'watch.digest', '--data', self.data]
        run = subprocess.run(base + ['--kind', 'evening', '--date', '2026-10-09'], capture_output=True, text=True)
        self.assertEqual((run.returncode, run.stdout.strip()), (0, 'd_2026-10-09_evening 2'))
        run = subprocess.run(base + ['--kind', 'morning', '--today', '2026-10-12'], capture_output=True, text=True)
        self.assertEqual((run.returncode, run.stdout.strip()), (0, 'd_2026-10-09_morning 2'))
        run = subprocess.run(base + ['--kind', 'morning', '--today', '2026-10-12'], capture_output=True, text=True)
        self.assertEqual((run.returncode, run.stdout), (0, ''))
