from contextlib import closing
import gzip
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest
from datetime import datetime, timezone


class IngestTests(unittest.TestCase):
    def setUp(self):
        from watch.ingest import ingest_source, store_raw
        self.ingest_source = ingest_source
        self.store_raw = store_raw
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.data = Path(self.temp.name)
        self.now = datetime(2026, 10, 12, 15, tzinfo=timezone.utc)
        self.body = gzip.decompress((Path(__file__).parent / "fixtures/members.xml.gz").read_bytes())

    def ingest(self, fetch=None):
        return self.ingest_source(self.data, "members", fetch=fetch or (lambda _url: self.body), now=self.now)

    def test_02_member_fixture(self):
        self.assertTrue(self.ingest())
        with closing(sqlite3.connect(self.data / "watch.db")) as db:
            self.assertEqual(db.execute("SELECT count(*) FROM members").fetchone()[0], 337)
            self.assertEqual(db.execute("SELECT name,party,riding,province FROM members WHERE person_id='123447'").fetchone(),
                             ("Billy Morin", "Conservative", "Edmonton Northwest", "Alberta"))

    def test_15_failed_ingest_preserves_data(self):
        self.assertTrue(self.ingest())
        def fail(_url):
            raise OSError("fixture fetch failure")
        self.assertFalse(self.ingest(fail))
        with closing(sqlite3.connect(self.data / "watch.db")) as db:
            self.assertEqual(db.execute("SELECT count(*) FROM members").fetchone()[0], 337)
            health = json.loads(db.execute("SELECT value FROM meta WHERE key='source:members'").fetchone()[0])
        self.assertFalse(health["ok"])
        self.assertTrue(health["error"])
        self.assertFalse(self.ingest(lambda _url: b"<broken"))
        with closing(sqlite3.connect(self.data / "watch.db")) as db:
            self.assertEqual(db.execute("SELECT count(*) FROM members").fetchone()[0], 337)

    def test_17_raw_deduplication(self):
        self.store_raw(self.data, "members", b"one", self.now)
        self.store_raw(self.data, "members", b"one", self.now)
        path = self.data / "raw/members/2026-10-12.jsonl.gz"
        with gzip.open(path, "rt") as raw:
            self.assertEqual(len(raw.readlines()), 1)
        self.store_raw(self.data, "members", b"two", self.now)
        with gzip.open(path, "rt") as raw:
            rows = [json.loads(line) for line in raw]
        self.assertEqual(len(rows), 2)
        self.assertEqual(set(rows[0]), {"at", "sha256", "body"})
        self.assertEqual(rows[0]["body"], "one")
        self.assertEqual(rows[0]["at"], "2026-10-12T15:00:00Z")
        self.assertNotEqual(rows[0]["sha256"], rows[1]["sha256"])
