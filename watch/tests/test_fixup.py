from datetime import datetime, timedelta, timezone
import io
import json
import tempfile
import unittest
from unittest.mock import patch

from watch import store
from watch.tests.test_feed import follows, paragraph
from watch.tests.test_records import fixture
from watch.tests.test_segment import seed, insert_lines

NOW = datetime(2026, 10, 12, 15, tzinfo=timezone.utc)


def official(data):
    from watch.poll import _save_transcript
    _save_transcript(data, fixture('HAN149-E.XML.gz'), fixture('HAN149-F.XML.gz'),
                     'hansard', 149, None, NOW)


class FixupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.data = self.temp.name

    def test_fixture_alignment(self):
        from watch.fixup import fixup
        from watch.segment import segment_event
        with store.connect(self.data) as db:
            index = seed(db)
            db.execute("UPDATE events SET scheduled_start='2026-10-09T14:00:00Z',actual_start='2026-10-09T14:01:04Z',actual_end='2026-10-09T18:31:27Z'")
            lines = json.loads(fixture('captions-45735-en.json.gz'))
            insert_lines(db, lines)
            segment_event(db, '45735', index)
        official(self.data)
        with store.connect(self.data) as db:
            counts = fixup(db, NOW)
            self.assertEqual(counts['superseded'], 527)
            self.assertGreaterEqual(counts['aligned'], 100)
            self.assertEqual({r[0] for r in db.execute("SELECT superseded_by FROM paragraphs WHERE source='captions'")}, {'hansard/45-1/149'})
            row = db.execute("SELECT * FROM paragraphs WHERE intervention='13631809' ORDER BY position").fetchone()
            self.assertEqual(row['intervention'], '13631809')
            self.assertEqual(row['offset_s'], 3800.281)
            line = next(r for r in lines if r['begin'] == '2026-10-09T15:03:54.281Z')
            self.assertIn('madam speaker, as we approach', line['text'].lower())
            self.assertLess(abs(row['offset_s'] - (datetime.fromisoformat(line['begin']) - datetime(2026, 10, 9, 14, 0, 34, tzinfo=timezone.utc)).total_seconds()), 1)
            meta = json.loads(db.execute("SELECT value FROM meta WHERE key='fixup:hansard/45-1/149'").fetchone()[0])
            self.assertEqual(meta['at'], '2026-10-12T15:00:00Z')
            self.assertEqual(meta['interventions'], 211)
            self.assertEqual(fixup(db, NOW), {k: 0 for k in counts})

    def test_wait_and_fallback(self):
        from watch.fixup import fixup
        with store.connect(self.data) as db:
            seed(db)
            db.execute("INSERT INTO documents VALUES ('hansard/45-1/149','hansard','45-1',149,NULL,'2026-10-09','url','now')")
            db.execute("UPDATE events SET actual_start='2026-10-09T14:01:04Z',actual_end=?", (store.iso(NOW - timedelta(hours=1)),))
            paragraph(db, 'inside', 'short', at='2026-10-09T14:02:00Z')
            paragraph(db, 'outside', 'short', at='2026-10-09T13:00:00Z')
            paragraph(db, 'caption', source='captions', event_id='45735')
            db.commit()
            self.assertEqual(fixup(db, NOW)['interventions'], 0)
            self.assertIsNone(db.execute("SELECT value FROM meta WHERE key LIKE 'fixup:%'").fetchone())
            self.assertIsNone(db.execute("SELECT superseded_by FROM paragraphs WHERE id='caption'").fetchone()[0])
            db.execute("UPDATE events SET actual_end='2026-10-09T18:31:27Z'")
            db.commit()
            self.assertEqual(fixup(db, NOW)['fallback'], 1)
            self.assertEqual(tuple(db.execute("SELECT event_id,offset_s FROM paragraphs WHERE id='inside'").fetchone()), ('45735', 86.0))
            self.assertEqual(tuple(db.execute("SELECT event_id,offset_s FROM paragraphs WHERE id='outside'").fetchone()), (None, None))
            self.assertIsNotNone(db.execute("SELECT value FROM meta WHERE key LIKE 'fixup:%'").fetchone())

    def test_worker_segment_and_failure(self):
        from watch import worker, fixup
        from watch.tests.test_match import fake_embed
        with store.connect(self.data) as db:
            seed(db)
            follows(db)
            insert_lines(db, json.loads(fixture('captions-45735-en.json.gz'))[:10])
            db.commit()
        output = io.StringIO()
        with patch('watch.embed.embed', side_effect=lambda texts, **_kwargs: fake_embed(texts)), patch.object(fixup, 'fixup', side_effect=RuntimeError('broken')), patch('sys.stderr', output):
            self.assertEqual(worker.main(['--data', self.data]), 0)
        result = json.loads(output.getvalue())
        self.assertGreater(result['segment'], 0)
        self.assertGreater(result['matches_added'], 0)
        self.assertIsNone(result['fixup'])
        with store.connect(self.data) as db:
            self.assertGreater(db.execute("SELECT count(*) FROM paragraphs WHERE source='captions'").fetchone()[0], 0)
            self.assertEqual(json.loads(db.execute("SELECT value FROM meta WHERE key='source:fixup'").fetchone()[0])['error'], 'broken')

    def test_missing_recording_no_offsets(self):
        from watch.fixup import fixup
        with store.connect(self.data) as db:
            seed(db)
            db.execute("INSERT INTO documents VALUES ('hansard/45-1/149','hansard','45-1',149,NULL,'2026-10-09','url','now')")
            db.execute("UPDATE events SET preroll_s=NULL")
            paragraph(db, 'aligned')
            insert_lines(db, [dict(event='45735', lang='en', source='archive', seq=0,
                                  begin='2026-10-09T14:00:00Z', end='2026-10-09T14:00:01Z',
                                  text='one two three four five six seven eight')])
            db.commit()
            result = fixup(db, NOW)
            self.assertEqual(result['aligned'], 1)
            self.assertEqual(tuple(db.execute("SELECT event_id,offset_s FROM paragraphs WHERE id='aligned'").fetchone()), ('45735', None))
