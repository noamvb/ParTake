import json
from pathlib import Path
import tempfile
import unittest

from watch.opinion.export import export


class OpinionExportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.out = Path(self.temp.name) / "snapshot"
        self.base = "http://127.0.0.1:8798"
        self.pages = {
            "/api/polls/summary": {"as_of": "2026-10-12", "note": {"text": "Libéraux"}},
            "/api/polls/leaders": {"best_pm": []},
            "/api/polls/list?region=CAN&limit=200": {"polls": [], "next": None},
            "/api/polls/ridings": {"ridings": [{"id": "24038"}, {"id": "35001"}]},
            "/api/polls/ridings/24038": {"id": "24038", "name": "Chicoutimi"},
            "/api/polls/ridings/35001": {"id": "35001", "name": "Ajax"},
        }
        self.requests = []

    def fetch(self, url):
        self.requests.append(url)
        responses = {self.base + path: value for path, value in self.pages.items()}
        return json.dumps(responses[url]).encode("utf-8")

    def test_A1_list_paging(self):
        self.pages["/api/polls/list?region=CAN&limit=200"] = {
            "polls": [{"id": "a"}], "next": "2026-10-01|b", "source": {"name": "first"},
        }
        self.pages["/api/polls/list?region=CAN&limit=200&before=2026-10-01%7Cb"] = {
            "polls": [{"id": "b"}], "next": "2026-09-01|c",
        }
        self.pages["/api/polls/list?region=CAN&limit=200&before=2026-09-01%7Cc"] = {
            "polls": [{"id": "c"}], "next": None,
        }
        export(self.base, self.out, self.fetch)
        self.assertEqual(json.loads((self.out / "list.json").read_bytes()), {
            "polls": [{"id": "a"}, {"id": "b"}, {"id": "c"}],
            "next": None, "source": {"name": "first"},
        })
        self.assertEqual(self.requests, [self.base + path for path in [
            "/api/polls/summary", "/api/polls/leaders",
            "/api/polls/list?region=CAN&limit=200",
            "/api/polls/list?region=CAN&limit=200&before=2026-10-01%7Cb",
            "/api/polls/list?region=CAN&limit=200&before=2026-09-01%7Cc",
            "/api/polls/ridings", "/api/polls/ridings/24038", "/api/polls/ridings/35001",
        ]])

    def test_A2_riding_files(self):
        self.out.mkdir()
        (self.out / "stale.json").write_text("old")
        self.assertTrue((self.out / "stale.json").exists())
        self.assertEqual(export(self.base, self.out, self.fetch), 6)
        self.assertEqual(sorted(p.name for p in (self.out / "ridings").iterdir()),
                         ["24038.json", "35001.json"])
        for riding_id in ["24038", "35001"]:
            self.assertEqual(json.loads((self.out / "ridings" / (riding_id + ".json")).read_bytes()),
                             self.pages["/api/polls/ridings/" + riding_id])
        self.assertFalse((self.out / "stale.json").exists())

    def test_A3_failure_preserves_existing_snapshot(self):
        self.out.mkdir()
        old = b'{"old":"summary"}'
        (self.out / "summary.json").write_bytes(old)

        def failing_fetch(url):
            if url == self.base + "/api/polls/ridings/35001":
                raise OSError("fetch failed")
            return self.fetch(url)

        with self.assertRaisesRegex(OSError, "fetch failed"):
            export(self.base, self.out, failing_fetch)
        self.assertEqual((self.out / "summary.json").read_bytes(), old)
        self.assertEqual(list(self.out.iterdir()), [self.out / "summary.json"])

    def test_A4_exact_encoder_output(self):
        export(self.base, self.out, self.fetch)
        self.assertEqual((self.out / "summary.json").read_bytes(),
                         '{"as_of":"2026-10-12","note":{"text":"Libéraux"}}'.encode("utf-8"))
