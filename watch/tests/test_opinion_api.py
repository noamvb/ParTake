from datetime import datetime, timezone
import http.client
import json
from pathlib import Path
import tempfile
import threading
import unittest
from urllib.error import HTTPError
from urllib.parse import quote

from watch.tests.test_opinion_sources import live_pages


NOW = datetime(2026, 10, 12, 15, tzinfo=timezone.utc)


class OpinionApiTests(unittest.TestCase):
    def setUp(self):
        from watch.api import make_server
        from watch.opinion.sources import poll_opinion
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.data = Path(self.temp.name)
        pages = live_pages()

        def fetch(url):
            if url not in pages:
                raise HTTPError(url, 404, "not found", None, None)
            return pages[url]

        self.assertTrue(poll_opinion(self.data, fetch, NOW))
        server = make_server(self.data, "127.0.0.1", 0, clock=lambda: NOW)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()

        def close():
            server.shutdown()
            server.server_close()
            thread.join()
        self.addCleanup(close)
        self.server = server

    def get(self, path):
        conn = http.client.HTTPConnection("127.0.0.1", self.server.server_port, timeout=3)
        conn.request("GET", path)
        response = conn.getresponse()
        result = response.status, json.loads(response.read())
        conn.close()
        return result

    def test_11_polls_list_pages_and_leaders(self):
        status, first = self.get("/api/polls/list?limit=2")
        self.assertEqual(status, 200)
        self.assertEqual(len(first["polls"]), 2)
        self.assertIsNotNone(first["next"])
        self.assertEqual(first["polls"][0]["id"], "338:2026-10-02:nanos-research")
        self.assertEqual(first["polls"][0]["shares"], {"LPC": 49, "CPC": 28, "NDP": 11, "GPC": 3, "BQ": 6, "OTH": 3})
        self.assertEqual(first["source"], {"name": "338Canada", "url": "https://338canada.com/polls.htm",
                                           "fetched_at": "2026-10-12T15:00:00Z"})

        status, second = self.get("/api/polls/list?limit=2&before=" + quote(first["next"]))
        self.assertEqual(status, 200)
        self.assertEqual(len(second["polls"]), 2)
        first_ids = {poll["id"] for poll in first["polls"]}
        self.assertFalse(first_ids & {poll["id"] for poll in second["polls"]})
        self.assertLessEqual(second["polls"][0]["end_date"], first["polls"][-1]["end_date"])

        status, quebec = self.get("/api/polls/list?region=QC&limit=200")
        self.assertEqual(status, 200)
        self.assertTrue(quebec["polls"])
        self.assertEqual({poll["region"] for poll in quebec["polls"]}, {"QC"})
        self.assertIsNone(quebec["next"])

        self.assertEqual(self.get("/api/polls/list?region=XX")[0], 400)
        self.assertEqual(self.get("/api/polls/list?limit=0")[0], 400)
        self.assertEqual(self.get("/api/polls/list?limit=201")[0], 400)
        self.assertEqual(self.get("/api/polls/list?limit=many")[0], 400)
        self.assertEqual(self.get("/api/polls/list?before=nope")[0], 400)

        status, leaders = self.get("/api/polls/leaders")
        self.assertEqual(status, 200)
        self.assertEqual(leaders["source"]["licence"], "CC BY-SA 4.0")
        self.assertEqual(leaders["source"]["name"], "Wikipedia")
        self.assertEqual(leaders["best_pm"][0]["firm"], "Nanos Research")
        self.assertEqual(leaders["best_pm"][0]["shares"]["Mark Carney"], 59.2)
        self.assertLessEqual(len(leaders["best_pm"]), 100)
        self.assertEqual(leaders["approval"][0], {"firm": "Liaison Strategies", "end_date": "2026-10-03",
                                                  "approve": 66, "disapprove": 27})
        self.assertEqual(len(leaders["approval"]), 100)
