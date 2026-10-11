"""Caption line commits and fixture-only recorder integration."""

from datetime import datetime, timedelta, timezone
import gzip
import json
from pathlib import Path
import tempfile
import unittest

from watch.cea608 import extract_cc_pairs
from watch.recorder import Lines, record, unwrap
from watch.store import connect


FIXTURES = Path(__file__).parent / "fixtures"
MASTER = "https://example.test/vod/playlist.m3u8"
QUERY = "?audioindex=1&wowzalanguage=eng"
MEDIA = "https://example.test/vod/chunklist.m3u8" + QUERY
SEGMENTS = ["https://example.test/vod/media_%s.ts" % n + QUERY for n in (27, 28)]
NOW = datetime(2026, 10, 9, 14, 6, tzinfo=timezone.utc)


def playlist(end=True):
    original = (FIXTURES / "hls-45735-chunklist.m3u8").read_text().splitlines()
    entries = []
    for i, line in enumerate(original):
        if line in ["media_%s.ts" % n + QUERY for n in (27, 28)]:
            entries.extend(original[i - 1:i + 1])
    return ("\n".join(["#EXTM3U", "#EXT-X-TARGETDURATION:12", "#EXT-X-MEDIA-SEQUENCE:27"]
                      + entries + (["#EXT-X-ENDLIST"] if end else [])) + "\n").encode()


class LinesTests(unittest.TestCase):
    def test_pop_on(self):
        lines = Lines()
        committed = []
        for pts, text in [(0, "A"), (10, None), (10, "B"), (20, None)]:
            committed.extend(lines.change(pts, text))
        self.assertEqual(committed, [("A", 0, 10), ("B", 10, 20)])

    def test_roll_up(self):
        lines = Lines()
        committed = []
        for pts, text in [(0, "Hel"), (5, "Hello"), (9, "Hello\nwor"),
                          (12, "Hello\nworld"), (20, "world\nnext")]:
            committed.extend(lines.change(pts, text))
        self.assertEqual(committed, [("Hello", 0, 20)])
        self.assertEqual(lines.flush(30), [("world", 9, 30), ("next", 20, 30)])
        self.assertEqual(lines.flush(40), [])

    def test_two_row_pop_on(self):
        lines = Lines()
        self.assertEqual(lines.change(0, "one\ntwo"), [])
        self.assertEqual(lines.change(10, "three"), [("one", 0, 10), ("two", 0, 10)])


class RecorderTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.data = self.temp.name
        self.urls = []
        self.sleeps = []
        self.media = playlist()
        with connect(self.data) as db, db:
            db.execute("INSERT INTO events(id,title,kind,number,document,scheduled_start,status,"
                       "has_archive,recording_start,preroll_s,stream_url,captions,updated_at) "
                       "VALUES ('45735','House sitting 149','house',149,'hansard/45-1/149',?,"
                       "-1,1,'2026-10-09T14:01:04Z',30,?,'none',?)", (NOW.isoformat(), MASTER, NOW.isoformat()))

    def fetch(self, url):
        self.urls.append(url)
        if url == MASTER:
            return (FIXTURES / "hls-45735-master.m3u8").read_bytes()
        if url == MEDIA:
            return self.media
        if url in SEGMENTS:
            return (FIXTURES / f"hls-45735-media_{27 + SEGMENTS.index(url)}.ts").read_bytes()
        self.fail("unexpected URL " + url)

    def run_record(self, **kwargs):
        return record(self.data, "45735", self.fetch, self.sleeps.append, lambda: NOW, **kwargs)

    def rows(self):
        with connect(self.data) as db:
            return [dict(row) for row in db.execute("SELECT * FROM captions ORDER BY seq")]

    def meta(self):
        with connect(self.data) as db:
            return json.loads(db.execute("SELECT value FROM meta WHERE key='recorder:45735'").fetchone()[0])

    def test_vod_end_to_end(self):
        self.assertEqual(self.run_record(), 0)
        rows = self.rows()
        oracle = json.loads((FIXTURES / "cea608-oracle-45735-27-28.json").read_text())
        self.assertEqual([row["text"] for row in rows], [text for pts, text in oracle if text is not None])
        self.assertEqual([row["seq"] for row in rows], list(range(len(rows))))
        self.assertTrue(all(row["source"] == "live" and row["lang"] == "en" for row in rows))
        archive = json.loads(gzip.decompress((FIXTURES / "captions-45735-en.json.gz").read_bytes()))
        for row in rows:
            same_text = [item for item in archive if item["text"] == row["text"]]
            self.assertTrue(same_text, row["text"])
            offset = min(abs((datetime.fromisoformat(row["begin"]) - datetime.fromisoformat(item["begin"])).total_seconds())
                         for item in same_text)
            self.assertLessEqual(offset, 1.5, (offset, row["text"]))
            self.assertRegex(row["begin"], r"\.\d{3}Z$")
            self.assertRegex(row["end"], r"\.\d{3}Z$")
        with connect(self.data) as db:
            self.assertEqual(db.execute("SELECT captions FROM events").fetchone()[0], "live")
        self.assertEqual(self.meta()["last_sequence"], 28)
        self.assertEqual(self.meta()["lines"], len(rows))
        self.assertEqual(self.urls, [MASTER, MEDIA, *SEGMENTS])

    def test_resume(self):
        self.assertEqual(self.run_record(), 0)
        before = self.rows()
        self.urls.clear()
        self.assertEqual(self.run_record(), 0)
        self.assertEqual(self.rows(), before)
        self.assertEqual(self.urls, [MASTER, MEDIA])

    def test_archive_preserved(self):
        with connect(self.data) as db, db:
            db.execute("UPDATE events SET captions='archive'")
        self.assertEqual(self.run_record(), 0)
        self.assertTrue(self.rows())
        with connect(self.data) as db:
            self.assertEqual(db.execute("SELECT captions FROM events").fetchone()[0], "archive")

    def test_live_anchor(self):
        self.media = playlist(False)
        self.assertEqual(self.run_record(max_loops=2), 0)
        first = self.rows()[0]
        pts = extract_cc_pairs((FIXTURES / "hls-45735-media_27.ts").read_bytes())[0][0]
        first_change = json.loads((FIXTURES / "cea608-oracle-45735-27-28.json").read_text())[0][0]
        expected = NOW - timedelta(seconds=20.02) + timedelta(seconds=(first_change - pts) / 90000)
        self.assertEqual(first["begin"], expected.isoformat(timespec="milliseconds").replace("+00:00", "Z"))
        anchor = self.meta()["anchor"]
        self.assertIsNotNone(anchor)
        self.assertEqual(self.sleeps, [6])
        self.assertEqual(self.urls, [MASTER, MEDIA, *SEGMENTS, MEDIA])
        self.assertEqual(self.run_record(max_loops=1), 0)
        self.assertEqual(self.meta()["anchor"], anchor)

    def test_missing_stream_and_fetch_failure(self):
        with connect(self.data) as db, db:
            db.execute("UPDATE events SET stream_url=NULL")
        self.assertEqual(self.run_record(), 2)
        self.assertEqual(self.urls, [])
        with connect(self.data) as db, db:
            db.execute("UPDATE events SET stream_url=?", (MASTER,))
        attempts = []

        def fail(url):
            attempts.append(url)
            raise OSError("offline")

        self.assertEqual(record(self.data, "45735", fail, self.sleeps.append, lambda: NOW), 1)
        self.assertEqual(attempts, [MASTER] * 4)
        self.assertEqual(len(self.sleeps), 3)

    def test_pts_unwrap(self):
        previous = 2**33 - 90000
        self.assertEqual(unwrap(1000, previous), 2**33 + 1000)
        self.assertGreater(unwrap(1000, previous), previous)
        self.assertEqual(unwrap(91000, 2**33 + 1000), 2**33 + 91000)
