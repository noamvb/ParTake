from contextlib import closing
import gzip
import http.client
import json
from pathlib import Path
import sqlite3
import tempfile
import threading
import unittest
from datetime import datetime, timedelta, timezone


FIXTURES = Path(__file__).parent / "fixtures"
NOW = datetime(2026, 10, 12, 15, tzinfo=timezone.utc)
SEAM = """{"version": 1, "follows": [
 {"id": "f_abc234", "kind": "house", "label": "House of Commons (chamber)", "created_at": "2026-10-12T15:00:00Z", "topic": null, "bill": null, "mp": null, "votes": null, "committee": null},
 {"id": "f_def567", "kind": "committee", "label": "ETHI", "created_at": "2026-10-12T15:00:01Z", "topic": null, "bill": null, "mp": null, "votes": null, "committee": {"code": "ETHI"}},
 {"id": "f_ghi234", "kind": "topic", "label": "Housing affordability", "created_at": "2026-10-12T15:00:02Z", "topic": {"phrases": {"en": "housing affordability", "fr": "abordabilité du logement"}, "keywords": ["CMHC"], "threshold": 0.55}, "bill": null, "mp": null, "votes": null, "committee": null},
 {"id": "f_jkl567", "kind": "bill", "label": "C-37", "created_at": "2026-10-12T15:00:03Z", "topic": null, "bill": {"id": "45-1/C-37", "number": "C-37", "title": "First Nations Clean Water Act"}, "mp": null, "votes": null, "committee": null},
 {"id": "f_mno234", "kind": "mp", "label": "Billy Morin", "created_at": "2026-10-12T15:00:04Z", "topic": null, "bill": null, "mp": {"person_id": "123447", "name": "Billy Morin", "party": "Conservative", "riding": "Edmonton Northwest"}, "votes": null, "committee": null},
 {"id": "f_pqr567", "kind": "votes", "label": "Party splits", "created_at": "2026-10-12T15:00:05Z", "topic": null, "bill": null, "mp": null, "votes": {"filter": "party_split"}, "committee": null},
 {"id": "f_stu234", "kind": "pm-qp", "label": "Prime Minister at Question Period", "created_at": "2026-10-12T15:00:06Z", "topic": null, "bill": null, "mp": null, "votes": null, "committee": null}
]}"""


class WatchApiTests(unittest.TestCase):
    def setUp(self):
        from watch.api import make_server
        self.make_server = make_server
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.data = Path(self.temp.name)
        self.start(clock=lambda: NOW)

    def start(self, **kwargs):
        server = self.make_server(self.data, "127.0.0.1", 0, **kwargs)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        def close():
            server.shutdown()
            server.server_close()
            thread.join()
        self.addCleanup(close)
        self.server = server

    def request(self, path, method="GET", value=None, token=True, raw=None):
        headers = {}
        if token is True:
            headers["Authorization"] = "Bearer " + (self.data / "token").read_text()
        elif isinstance(token, str):
            headers["Authorization"] = token
        body = raw if raw is not None else json.dumps(value).encode() if value is not None else None
        conn = http.client.HTTPConnection("127.0.0.1", self.server.server_port, timeout=3)
        conn.request(method, path, body, headers)
        response = conn.getresponse()
        result = response.status, json.loads(response.read())
        self.assertEqual(response.getheader("Content-Type"), "application/json")
        self.assertEqual(response.getheader("Cache-Control"), "no-store")
        conn.close()
        return result

    def ingest(self, source):
        from watch.ingest import ingest_source
        name = source + ".xml.gz" if source != "bills" else "legisinfo-bills.json"
        body = (FIXTURES / name).read_bytes()
        if name.endswith(".gz"):
            body = gzip.decompress(body)
        self.assertTrue(ingest_source(self.data, source, fetch=lambda _url: body, now=NOW))

    def two(self):
        follows = json.loads(SEAM)["follows"]
        return [{k: v for k, v in follows[i].items() if k not in ("id", "created_at")} for i in (2, 4)]

    def put_two(self):
        status, body = self.request("/api/follows", "PUT", {"version": 0, "follows": self.two()})
        self.assertEqual(status, 200)
        return body

    def test_03_ministry_roles(self):
        self.ingest("members")
        self.ingest("ministries")
        self.assertEqual(self.request("/api/members?q=carney")[1][0]["person_id"], "28286")
        self.assertEqual(self.request("/api/members?q=carney")[1][0]["role"], "Prime Minister")
        self.assertIsNone(self.request("/api/members?q=morin")[1][0]["role"])
        from watch.ingest import ingest_source
        body = gzip.decompress((FIXTURES / "ministries.xml.gz").read_bytes())
        extra = b"""
        <Minister><PersonId>28286</PersonId><Title>Later title</Title><OrderOfPrecedence>10</OrderOfPrecedence><ToDateTime xsi:nil="true"/></Minister>
        <Minister><PersonId>28286</PersonId><Title>Second title</Title><OrderOfPrecedence>2</OrderOfPrecedence><ToDateTime xsi:nil="true"/></Minister>
        <Minister><PersonId>28286</PersonId><Title>Former title</Title><OrderOfPrecedence>0</OrderOfPrecedence><ToDateTime>2020-01-01</ToDateTime></Minister>
        """
        body = body.replace(b"</ArrayOfMinister>", extra + b"</ArrayOfMinister>")
        self.assertTrue(ingest_source(self.data, "ministries", fetch=lambda _url: body, now=NOW))
        self.assertEqual(self.request("/api/members?q=carney")[1][0]["role"],
                         "Prime Minister; Second title; Later title")

    def test_04_ranking_accents_and_limit(self):
        self.ingest("members")
        self.assertEqual(self.request("/api/members?q=morin")[1][0]["person_id"], "123447")
        self.assertIn("123208", [m["person_id"] for m in self.request("/api/members?q=belanger")[1]])
        self.assertIn("104977", [m["person_id"] for m in self.request("/api/members?q=sherbrooke")[1]])
        self.assertEqual(len(self.request("/api/members?q=e")[1]), 20)
        with closing(sqlite3.connect(self.data / "watch.db")) as db, db:
            db.executemany("INSERT INTO members VALUES (?,?,?,?,?,?,?)", [
                ("rank1", "Zoe Qrank", "", "", "", "Zoe", "Qrank"),
                ("rank2", "Qrank Able", "", "", "", "Qrank", "Able"),
                ("rank3", "Alex Someqrank", "", "", "", "Alex", "Someqrank"),
                ("rank0", "Alex Qrank", "", "", "", "Alex", "Qrank"),
            ])
        self.assertEqual([m["person_id"] for m in self.request("/api/members?q=qrank")[1]],
                         ["rank0", "rank1", "rank2", "rank3"])

    def test_05_missing_member_query(self):
        for path in ("/api/members", "/api/members?q=%20"):
            self.assertEqual(self.request(path)[0], 400)

    def test_06_bill_lookup(self):
        self.ingest("bills")
        expected = {"id": "45-1/C-37", "number": "C-37", "title": "First Nations Clean Water Act",
                    "stage": "At consideration in committee in the House of Commons", "stage_at": "2026-10-09T17:20:48Z"}
        for query in ("c37", "C-37", "c-37"):
            self.assertEqual(self.request("/api/bills?q=" + query)[1][0], expected)
        rail = self.request("/api/bills?q=railways")[1][0]
        self.assertEqual((rail["id"], rail["title"]), ("45-1/S-1", "An Act relating to railways"))
        self.assertEqual([b["id"] for b in self.request("/api/bills?q=c-2")[1]], ["45-1/C-2"])

    def test_07_unauthorized(self):
        for token in (False, "Bearer wrong"):
            self.assertEqual(self.request("/api/follows", "PUT", {"version": 0, "follows": self.two()},
                                          token=token), (401, {"error": "unauthorized"}))
        self.assertEqual(self.request("/api/follows")[1]["version"], 0)

    def test_08_create_follows(self):
        body = self.put_two()
        self.assertEqual(body["version"], 1)
        for follow in body["follows"]:
            self.assertRegex(follow["id"], r"^f_[a-z2-7]{6}$")
            self.assertRegex(follow["created_at"], r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$")
            self.assertTrue({"topic", "bill", "mp", "votes", "committee"}.issubset(follow))

    def test_09_stale_version(self):
        current = self.put_two()
        self.assertEqual(self.request("/api/follows", "PUT", {"version": 0, "follows": []}), (409, current))
        self.assertEqual(self.request("/api/follows")[1], current)

    def test_10_validation_atomicity(self):
        invalid = [
            [{"kind": "unknown", "label": "x"}],
            [{"kind": "topic", "label": "x", "mp": self.two()[1]["mp"], "topic": self.two()[0]["topic"]}],
            [{"kind": "mp", "label": "x", "mp": {"person_id": "1"}}],
            [{"kind": "topic", "label": "x", "topic": {"phrases": {"en": "x", "fr": ""}, "keywords": [], "threshold": 2}}],
            [{"kind": "votes", "label": "x", "votes": {"filter": "some"}}],
            [{"kind": "house", "label": "x", "id": "f_absent"}],
            [{"kind": "house", "label": "a"}, {"kind": "house", "label": "b"}],
            [{"kind": "pm-qp", "label": "a"}, {"kind": "pm-qp", "label": "b"}],
            [{"kind": "committee", "label": "a", "committee": {"code": "ETHI"}},
             {"kind": "committee", "label": "b", "committee": {"code": "ETHI"}}],
            [{"kind": "house"}], [{"kind": "house", "label": ""}],
            [{"kind": "topic", "label": "x", "topic": {"phrases": {"en": 1, "fr": ""}, "keywords": [], "threshold": .5}}],
        ]
        for follows in invalid:
            with self.subTest(follows=follows):
                self.assertEqual(self.request("/api/follows", "PUT", {"version": 0, "follows": follows})[0], 400)
        self.assertEqual(self.request("/api/follows")[1], {"version": 0, "follows": []})

    def test_11_soft_remove(self):
        current = self.put_two()
        removed = current["follows"].pop()
        status, result = self.request("/api/follows", "PUT", current)
        self.assertEqual((status, result["version"]), (200, 2))
        self.assertEqual(result["follows"], current["follows"])
        self.assertEqual(self.request("/api/follows")[1], result)
        with closing(sqlite3.connect(self.data / "watch.db")) as db:
            self.assertIsNotNone(db.execute("SELECT removed_at FROM follows WHERE id=?", (removed["id"],)).fetchone()[0])

    def test_12_import_idempotent(self):
        status, body = self.request("/api/follows/import", "POST", {"keys": ["ETHI", "PM-QP", "HOC"]})
        self.assertEqual((status, body["version"]), (200, 1))
        self.assertEqual([(f["kind"], f["label"]) for f in body["follows"]],
                         [("committee", "ETHI"), ("pm-qp", "Prime Minister at Question Period"),
                          ("house", "House of Commons (chamber)")])
        self.assertEqual(self.request("/api/follows/import", "POST", {"keys": ["ETHI", "PM-QP", "HOC"]}), (200, body))
        result = self.request("/api/follows/import", "POST", {"keys": ["ETHI", "FEWO"]})[1]
        self.assertEqual((result["version"], len(result["follows"])), (2, 4))

    def test_13_seam_literal(self):
        expected = json.loads(SEAM)
        ids = iter(f["id"] for f in expected["follows"])
        times = iter(NOW + timedelta(seconds=i) for i in range(7))
        self.start(clock=lambda: next(times), new_id=lambda: next(ids))
        follows = [{k: v for k, v in f.items() if k not in ("id", "created_at")} for f in expected["follows"]]
        self.assertEqual(self.request("/api/follows", "PUT", {"version": 0, "follows": follows}), (200, expected))
        self.assertEqual(self.request("/api/follows")[1], expected)

    def test_14_health(self):
        self.start(clock=lambda: NOW, ollama="http://127.0.0.1:0")
        self.ingest("members")
        status, health = self.request("/api/health")
        self.assertEqual(status, 200)
        self.assertTrue(health["ok"])
        self.assertEqual((health["version"], health["now"]), ("0.1.0", "2026-10-12T15:00:00Z"))
        self.assertEqual(set(health["sources"]), {"members"})
        self.assertEqual(health["sources"]["members"], {"at": "2026-10-12T15:00:00Z", "ok": True, "error": None})
        self.assertEqual([health[k] for k in ("sitting_today", "recorders", "embed", "backfill")], [None, [], {"model": "paraphrase-multilingual", "loaded": False}, None])

    def test_16_token_persistence(self):
        token = (self.data / "token").read_text()
        self.assertTrue(token)
        self.assertEqual((self.data / "token").stat().st_mode & 0o777, 0o600)
        self.start(clock=lambda: NOW)
        self.assertEqual((self.data / "token").read_text(), token)
        self.assertEqual(self.request("/api/follows", "PUT", {"version": 0, "follows": []}),
                         (200, {"version": 1, "follows": []}))

    def test_18_unknown_and_bad_json(self):
        self.assertEqual(self.request("/api/nope")[0], 404)
        self.assertEqual(self.request("/api/follows", "PUT", raw=b"{not json")[0], 400)
        self.assertEqual(self.request("/api/follows", "PUT", raw=b"null")[0], 400)
        # Declare the size only: the server answers 413 before reading, so a
        # real 1 MiB body races the response and can end in a broken pipe.
        conn = http.client.HTTPConnection("127.0.0.1", self.server.server_port, timeout=3)
        conn.putrequest("PUT", "/api/follows")
        conn.putheader("Authorization", "Bearer " + (self.data / "token").read_text())
        conn.putheader("Content-Length", str(1024 * 1024 + 1))
        conn.endheaders()
        response = conn.getresponse()
        self.assertEqual((response.status, json.loads(response.read())), (413, {"error": "body too large"}))
        conn.close()
        self.assertEqual(self.request("/api/follows")[1]["version"], 0)
