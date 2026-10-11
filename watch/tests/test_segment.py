import json
import tempfile
import unittest

from watch.ingest import parse_members, parse_ministries
from watch.store import connect
from watch.tests.test_records import fixture


EVENTS = {
    '45735': dict(kind='house', committee=None, number=149, document='hansard/45-1/149',
                  recording_start='2026-10-09T14:01:04Z'),
    '45822': dict(kind='committee', committee='INDU', number=50, document='evidence/45-1/INDU/50',
                  recording_start='2026-10-06T15:04:02Z'),
}


def seed(db, event='45735', *, source='archive', status=-1):
    values = dict(EVENTS[event], id=event, status=status, captions=source)
    db.execute('INSERT INTO events(id,title,kind,committee,number,document,scheduled_start,status,has_archive,'
               'recording_start,preroll_s,captions,updated_at) '
               "VALUES (:id,'event',:kind,:committee,:number,:document,:recording_start,:status,1,:recording_start,30,:captions,'now')", values)
    members, ministries = parse_members(fixture('members.xml.gz')), parse_ministries(fixture('ministries.xml.gz'))
    db.executemany('INSERT OR IGNORE INTO members VALUES (?,?,?,?,?,?,?)', members)
    db.executemany('INSERT OR IGNORE INTO ministries VALUES (?,?,?)', ministries)
    from watch.speaker import CallIndex
    return CallIndex(members, ministries)


def insert_lines(db, rows):
    db.executemany('INSERT INTO captions VALUES (:event,:lang,:source,:seq,:begin,:end,:text)', rows)


def paragraphs(db, event='45735'):
    return [dict(row) for row in db.execute('SELECT * FROM paragraphs WHERE document=? ORDER BY position', ('captions/' + event,))]


class SegmentTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.rows = json.loads(fixture('captions-45735-en.json.gz'))

    def test_05_archive(self):
        from watch.segment import segment_event
        with connect(self.temp.name) as db, db:
            index = seed(db)
            insert_lines(db, self.rows)
            count = segment_event(db, '45735', index)
            rows = paragraphs(db)
            self.assertEqual(count, 527)
            self.assertEqual(len(rows), count)
            self.assertTrue(300 < count < 1500)
            self.assertEqual(rows[0]['at'], '2026-10-09T14:00:40.190Z')
            self.assertEqual(rows[0]['offset_s'], 6.19)
            self.assertEqual([r['at'] for r in rows], sorted(r['at'] for r in rows))
            for i, row in enumerate(rows):
                self.assertEqual(row['id'], f'c45735_{i}')
                self.assertEqual(row['position'], i)
                self.assertRegex(row['intervention'], r'^c45735_\d+$')
                self.assertEqual((row['document'], row['title'], row['source'], row['lang'], row['text_fr']),
                                 ('captions/45735', 'House of Commons, sitting 149', 'captions', 'en', ''))
                self.assertLessEqual(len(row['text_en'].split()), 200)
                self.assertEqual(row['text_en'], ' '.join(row['text_en'].split()))
            self.assertEqual(rows[0]['text_en'], '>> The Speaker: Orders day.')

    def test_06_incremental(self):
        from watch.segment import segment_event
        with tempfile.TemporaryDirectory() as other, connect(other) as expected, expected, connect(self.temp.name) as db, db:
            index = seed(db)
            seed(expected)
            insert_lines(expected, self.rows)
            segment_event(expected, '45735', index)
            for start in range(0, len(self.rows), 2109):
                insert_lines(db, self.rows[start:start + 2109])
                segment_event(db, '45735', index)
            def without_seq(rows):
                return [{k: v for k, v in r.items() if k != 'seq'} for r in rows]
            self.assertEqual(without_seq(paragraphs(db)), without_seq(paragraphs(expected)))
            self.assertEqual(segment_event(db, '45735', index), 0)
            meta = json.loads(db.execute("SELECT value FROM meta WHERE key='segment:45735'").fetchone()[0])
            self.assertEqual(meta['source'], 'archive')
            self.assertIn('cursor', meta)
            self.assertIn('next_speech', meta)
            self.assertIn('next_position', meta)
            self.assertIn('pending', meta)

    def synthetic(self, db, texts, source='archive', status=-1):
        index = seed(db, source=source, status=status)
        rows = [dict(event='45735', lang='en', source=source, seq=i,
                     begin=f'2026-10-09T14:01:{i:02d}.123Z', end=f'2026-10-09T14:01:{i + 1:02d}.123Z', text=t)
                for i, t in enumerate(texts)]
        insert_lines(db, rows)
        return index

    def test_07_speaker_flow(self):
        from watch.segment import segment_event
        with connect(self.temp.name) as db, db:
            index = self.synthetic(db, ['>> The Speaker: The honourable member for Edmonton Northwest.',
                '>> Mr. Speaker, I rise to speak.', '>> Interpreter: Translation of the same speech.',
                '>> The Speaker: The honourable minister of Indigenous Services.', '>> Thank you for calling me.',
                '>> An uncalled member speaks.'])
            segment_event(db, '45735', index)
            rows = paragraphs(db)
            self.assertEqual([r['person_id'] for r in rows], [None, '123447', '123447', None, '122492', None])
            self.assertEqual(rows[0]['speaker'], 'The Speaker')
            self.assertIsNone(rows[0]['confidence'])
            self.assertEqual(rows[1]['speaker'], 'Billy Morin')
            self.assertEqual(rows[2]['confidence'], 0.9)
            self.assertEqual(rows[4]['confidence'], 0.85)

    def test_08_live_tail(self):
        from watch.segment import segment_event
        with connect(self.temp.name) as db, db:
            index = self.synthetic(db, ['>> A speech awaiting the next marker.'], source='live', status=1)
            self.assertEqual(segment_event(db, '45735', index), 0)
            insert_lines(db, [dict(event='45735', lang='en', source='live', seq=1,
                                  begin='2026-10-09T14:02:00.123Z', end='2026-10-09T14:02:01.123Z',
                                  text='Additional words. >> The next speech.')])
            self.assertEqual(segment_event(db, '45735', index), 1)
            self.assertEqual(paragraphs(db)[0]['text_en'], '>> A speech awaiting the next marker. Additional words.')
            self.assertEqual(segment_event(db, '45735', index), 0)
            archive = json.loads(fixture('captions-45735-en.json.gz'))[:5]
            insert_lines(db, archive)
            db.execute("UPDATE events SET captions='archive',status=-1")
            self.assertEqual(segment_event(db, '45735', index), 0)
            self.assertEqual(json.loads(db.execute("SELECT value FROM meta WHERE key='segment:45735'").fetchone()[0])['source'], 'live')

    def test_09_official_skipped(self):
        from watch.segment import segment_all
        with connect(self.temp.name) as db, db:
            index = seed(db)
            insert_lines(db, self.rows)
            db.execute("INSERT INTO documents VALUES ('hansard/45-1/149','hansard','45-1',149,NULL,'2026-10-09','url','now')")
            self.assertEqual(segment_all(db, index), 0)
            self.assertEqual(paragraphs(db), [])
