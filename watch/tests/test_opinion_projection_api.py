from datetime import date, datetime, timedelta, timezone
import http.client
import json
from pathlib import Path
import tempfile
import threading
import unittest
from urllib.error import HTTPError

from watch.opinion.projection import recompute
from watch.opinion.swing import PARTIES
from watch.store import connect
from watch.tests.test_opinion_sources import live_pages


NOW = datetime(2026, 10, 12, 15, tzinfo=timezone.utc)
REGIONS = {"CAN", "ATL", "QC", "ON", "PR", "AB", "BC"}


class PollsDataTests(unittest.TestCase):
    def fill(self):
        """A data dir with P1's polls and the 3-riding 2025 sample, projected through NOW."""
        from watch.opinion.sources import poll_opinion
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.data = Path(temp.name)
        pages = live_pages()

        def fetch(url):
            if url not in pages:
                raise HTTPError(url, 404, "not found", None, None)
            return pages[url]

        self.assertTrue(poll_opinion(self.data, fetch, NOW))
        self.serve()

    def empty(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.data = Path(temp.name)
        self.serve()

    def serve(self):
        from watch.api import make_server
        server = make_server(self.data, "127.0.0.1", 0, clock=lambda: NOW)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()

        def close():
            server.shutdown()
            server.server_close()
            thread.join()
        self.addCleanup(close)
        self.port = server.server_port

    def get(self, path):
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=10)
        conn.request("GET", path)
        response = conn.getresponse()
        result = response.status, json.loads(response.read())
        conn.close()
        return result

    def add_member(self, person_id, name, party, riding, province, first, last):
        with connect(self.data) as db, db:
            db.execute("INSERT INTO members VALUES (?,?,?,?,?,?,?)",
                       (person_id, name, party, riding, province, first, last))


class OpinionProjectionTests(PollsDataTests):
    def test_12_recompute_covers_every_day_for_the_sample_ridings(self):
        self.fill()
        with connect(self.data) as db:
            ridings = {row[0] for row in db.execute("SELECT DISTINCT riding FROM riding_projections")}
            dates = [row[0] for row in db.execute("SELECT date FROM projections ORDER BY date")]
        self.assertEqual(ridings, {"10001", "24001", "60001"})
        self.assertEqual(dates[-1], "2026-10-12")
        first = date.fromisoformat(dates[0])
        self.assertGreater(first, date(2025, 4, 28))
        self.assertEqual([date.fromisoformat(day) for day in dates],
                         [first + timedelta(days=n) for n in range(len(dates))])
        self.assertEqual(recompute(self.data, NOW), len(dates))


class OpinionPollsApiTests(PollsDataTests):
    def test_13_summary_shape(self):
        self.fill()
        status, body = self.get("/api/polls/summary")
        self.assertEqual(status, 200)
        self.assertEqual(set(body), {"as_of", "polls_used", "average", "seats", "majority", "minority", "seats_total",
                                     "majority_line", "comparison", "note", "history"})
        self.assertEqual(body["as_of"], "2026-10-12")
        self.assertIsNone(body["majority"])
        self.assertIsNone(body["minority"])
        self.assertEqual(body["seats_total"], 343)
        self.assertEqual(body["majority_line"], 172)
        self.assertIn("CAN", body["average"])
        self.assertLessEqual(set(body["average"]), REGIONS)
        self.assertEqual(set(body["seats"]), set(PARTIES))
        for counts in body["seats"].values():
            self.assertEqual(counts["low"], counts["median"])
            self.assertEqual(counts["high"], counts["median"])
        self.assertEqual(sum(counts["median"] for counts in body["seats"].values()), 3)
        dates = [entry["date"] for entry in body["history"]]
        self.assertEqual(dates, sorted(dates))
        self.assertEqual(dates[-1], "2026-10-12")
        self.assertEqual(set(body["history"][-1]), {"date", "average", "seats"})
        self.assertEqual(set(body["history"][-1]["seats"]), set(PARTIES))
        status, short = self.get("/api/polls/summary?history=0")
        self.assertEqual(status, 200)
        self.assertEqual(short["history"], [])

    def test_14_summary_before_any_projection(self):
        self.empty()
        status, body = self.get("/api/polls/summary")
        self.assertEqual(status, 404)
        self.assertEqual(body, {"error": "no projection yet"})

    def test_15_ridings_order_and_mp_lookup(self):
        self.fill()
        status, body = self.get("/api/polls/ridings")
        self.assertEqual(status, 200)
        names = [riding["name"] for riding in body["ridings"]]
        self.assertEqual(len(names), 3)
        self.assertEqual(names, sorted(names))
        self.add_member("1001", "Paul Connors", "Liberal", "Avalon", "Newfoundland and Labrador", "Paul", "Connors")
        # Renamed riding: the MP is linked through the 2025 winner's family name in the same province.
        self.add_member("2001", "Mandy Gull-Masty", "NDP", "Abitibi (renamed)", "Quebec", "Mandy", "Gull-Masty")
        status, body = self.get("/api/polls/ridings?mp=1001")
        self.assertEqual(status, 200)
        self.assertEqual([riding["id"] for riding in body["ridings"]], ["10001"])
        self.assertEqual(body["ridings"][0]["mp"], {"person_id": "1001", "name": "Paul Connors", "party": "LPC"})
        self.assertEqual(body["ridings"][0]["won_2025"], "LPC")
        status, body = self.get("/api/polls/ridings?mp=2001")
        self.assertEqual(status, 200)
        self.assertEqual([riding["id"] for riding in body["ridings"]], ["24001"])
        self.assertEqual(self.get("/api/polls/ridings?mp=9999")[0], 404)

    def test_16_status_rules(self):
        self.fill()
        self.add_member("1001", "Paul Connors", "Liberal", "Avalon", "Newfoundland and Labrador", "Paul", "Connors")

        def set_projection(winner, margin):
            with connect(self.data) as db, db:
                db.execute("UPDATE riding_projections SET winner=?, margin=? WHERE riding='10001' AND date='2026-10-12'",
                           (winner, margin))

        for margin, status_name in ((12, "safe"), (7, "likely"), (2, "at_risk")):
            set_projection("LPC", margin)
            status, body = self.get("/api/polls/ridings?mp=1001")
            self.assertEqual(status, 200)
            self.assertEqual(body["ridings"][0]["status"], status_name, margin)
            self.assertEqual(body["ridings"][0]["projected"], "LPC")
        set_projection("CPC", 12)
        self.assertEqual(self.get("/api/polls/ridings?mp=1001")[1]["ridings"][0]["status"], "projected_loss")

    def test_17_riding_detail(self):
        self.fill()
        status, body = self.get("/api/polls/ridings/10001")
        self.assertEqual(status, 200)
        self.assertEqual(body["id"], "10001")
        self.assertEqual(set(body["results_2025"]), set(PARTIES))
        self.assertAlmostEqual(sum(body["results_2025"].values()), 100, delta=0.5)
        self.assertEqual(set(body["projection"]), set(PARTIES))
        self.assertEqual(body["history"][-1]["date"], "2026-10-12")
        self.assertEqual(body["history"][-1]["shares"], body["projection"])
        dates = [entry["date"] for entry in body["history"]]
        self.assertEqual(dates, sorted(dates))
        self.assertEqual(self.get("/api/polls/ridings/99999")[0], 404)
