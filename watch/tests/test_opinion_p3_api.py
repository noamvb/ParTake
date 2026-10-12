from datetime import date, datetime, timedelta, timezone
import http.client
import json
from pathlib import Path
import tempfile
import threading
import unittest
from urllib.error import HTTPError

from watch import store
from watch.api import make_server
from watch.digest import build
from watch.opinion.comparison import parse_338_seats
from watch.opinion.sources import poll_opinion
from watch.opinion.swing import PARTIES
from watch.store import connect
from watch.tests.test_opinion_sources import fixture, live_pages


NOW = datetime(2026, 10, 12, 15, tzinfo=timezone.utc)
URL_FRONT = "https://338canada.com/federal.htm"
FEDERAL = "338-federal-2026-10-12.html.gz"


def pages_fetch(pages):
    def fetch(url):
        if url not in pages:
            raise HTTPError(url, 404, "not found", None, None)
        return pages[url]
    return fetch


def projection_body(lpc, cpc, sim=None):
    seats = {"LPC": lpc, "CPC": cpc, "NDP": 12, "BQ": 9, "GPC": 2, "OTH": 343 - lpc - cpc - 23}
    found = {"average": {"CAN": dict.fromkeys(PARTIES, 10.0)}, "polls_used": 1, "seats": {"CAN": seats}}
    if sim is not None:
        found["sim"] = sim
    return found


class P3Base(unittest.TestCase):
    def setup_data(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.data = Path(temp.name)

    def fill(self, now=NOW, pages=None):
        pages = live_pages() if pages is None else pages
        self.assertTrue(poll_opinion(self.data, pages_fetch(pages), now))

    def serve(self):
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

    def with_front_page(self):
        pages = live_pages()
        pages[URL_FRONT] = fixture(FEDERAL)
        return pages


class ParseSeatsTests(unittest.TestCase):
    def test_10_fixture_seat_projection(self):
        found = parse_338_seats(fixture(FEDERAL))
        self.assertEqual(found, {"as_of": "2026-10-11",
                                 "seats": {"LPC": 239, "CPC": 71, "NDP": 12, "GPC": 2, "BQ": 19, "OTH": 0}})

    def test_11_page_without_the_block(self):
        self.assertIsNone(parse_338_seats(b"<html><script>window.demopoll_TABLE_DATA = {}</script></html>"))
        self.assertIsNone(parse_338_seats(fixture("338-polls-2026-10-12.html.gz")))


class P3ApiTests(P3Base):
    def test_12_summary_with_odds_comparison_and_note(self):
        self.setup_data()
        self.fill(pages=self.with_front_page())
        self.serve()
        status, body = self.get("/api/polls/summary")
        self.assertEqual(status, 200)
        self.assertEqual(set(body["majority"]), set(PARTIES))
        self.assertEqual(set(body["minority"]), set(PARTIES))
        for party in PARTIES:
            self.assertGreaterEqual(body["majority"][party], 0.0)
            self.assertLessEqual(body["majority"][party], 1.0)
            stats = body["seats"][party]
            self.assertLessEqual(stats["low"], stats["median"], party)
            self.assertLessEqual(stats["median"], stats["high"], party)
        self.assertEqual(body["comparison"], {"name": "338Canada", "as_of": "2026-10-11",
                                              "seats": {"LPC": 239, "CPC": 71, "NDP": 12, "GPC": 2, "BQ": 19, "OTH": 0}})
        self.assertEqual(date.fromisoformat(body["note"]["week_of"]).weekday(), 0)
        self.assertTrue(body["note"]["text"].endswith("."))
        status, short = self.get("/api/polls/summary?history=0")
        self.assertEqual(short["note"], body["note"])

    def test_12b_note_is_null_with_a_single_sunday(self):
        self.setup_data()
        with connect(self.data) as db, db:
            db.execute("INSERT INTO projections VALUES (?,?)", ("2026-10-11", json.dumps(projection_body(199, 99))))
        self.serve()
        status, body = self.get("/api/polls/summary")
        self.assertEqual(status, 200)
        self.assertIsNone(body["note"])
        self.assertIsNone(body["comparison"])
        self.assertIsNone(body["majority"])
        self.assertEqual(body["seats"]["LPC"], {"median": 199, "low": 199, "high": 199})

    def test_13_failed_front_page_keeps_the_stored_projection(self):
        self.setup_data()
        self.fill(pages=self.with_front_page())
        with connect(self.data) as db:
            stored = db.execute("SELECT value FROM meta WHERE key='opinion:338_seats'").fetchone()[0]
        pages = live_pages()
        self.fill(now=NOW + timedelta(days=1), pages=pages)
        with connect(self.data) as db:
            self.assertEqual(db.execute("SELECT value FROM meta WHERE key='opinion:338_seats'").fetchone()[0], stored)
            self.assertTrue(json.loads(db.execute("SELECT value FROM meta WHERE key='source:opinion'").fetchone()[0])["ok"])
        # A page that loads but has no seat block is also a failure that leaves the value alone.
        pages = live_pages()
        pages[URL_FRONT] = b"<html>no chart here</html>"
        self.fill(now=NOW + timedelta(days=2), pages=pages)
        with connect(self.data) as db:
            self.assertEqual(db.execute("SELECT value FROM meta WHERE key='opinion:338_seats'").fetchone()[0], stored)

    def test_14_ridings_status_and_win_prob_from_probs(self):
        self.setup_data()
        self.fill()
        self.serve()
        self.add_member("1001", "Paul Connors", "Liberal", "Avalon", "Newfoundland and Labrador", "Paul", "Connors")

        def set_last(winner, probs):
            with connect(self.data) as db, db:
                db.execute("UPDATE riding_projections SET winner=?, probs=? WHERE riding='10001' AND date='2026-10-12'",
                           (winner, json.dumps(probs)))

        def listed():
            status, body = self.get("/api/polls/ridings?mp=1001")
            self.assertEqual(status, 200)
            return body["ridings"][0]

        for chance, expected in ((0.95, "safe"), (0.8, "likely"), (0.5, "at_risk")):
            set_last("LPC", {"LPC": chance, "CPC": 1 - chance})
            self.assertEqual(listed()["status"], expected, chance)
            self.assertEqual(listed()["win_prob"], round(chance, 2))
        set_last("LPC", {"LPC": 0.9537, "CPC": 0.0463})
        self.assertEqual(listed()["win_prob"], 0.95)
        set_last("CPC", {"CPC": 0.6, "LPC": 0.4})
        self.assertEqual(listed()["status"], "projected_loss")
        self.assertEqual(listed()["projected"], "CPC")
        self.assertEqual(listed()["win_prob"], 0.6)
        status, detail = self.get("/api/polls/ridings/10001")
        self.assertEqual(detail["probs"], {"CPC": 0.6, "LPC": 0.4})

    def test_15_first_seen_is_kept_and_p2_database_is_migrated(self):
        self.setup_data()
        self.fill()
        with connect(self.data) as db:
            first = {(row[0], row[1]): row[2] for row in db.execute("SELECT id, region, first_seen FROM opinion_polls")}
            fetched = {row[0] for row in db.execute("SELECT fetched_at FROM opinion_polls")}
        self.assertTrue(first)
        self.assertEqual(set(first.values()), {"2026-10-12T15:00:00Z"})
        self.fill(now=NOW + timedelta(days=1))
        with connect(self.data) as db:
            self.assertEqual({(row[0], row[1]): row[2] for row in db.execute(
                "SELECT id, region, first_seen FROM opinion_polls")}, first)
            later = {row[0] for row in db.execute("SELECT fetched_at FROM opinion_polls")}
        self.assertNotEqual(later, fetched)
        # A poll that leaves the table and comes back is seen again on its return.
        with connect(self.data) as db, db:
            poll_id, region = next(iter(first))
            db.execute("DELETE FROM opinion_polls WHERE id=? AND region=?", (poll_id, region))
        self.fill(now=NOW + timedelta(days=2))
        with connect(self.data) as db:
            again = db.execute("SELECT first_seen FROM opinion_polls WHERE id=? AND region=?", (poll_id, region)).fetchone()[0]
        self.assertEqual(again, "2026-10-14T15:00:00Z")

        # A database as P2 left it: no first_seen, no probs, no opinion_notes.
        with connect(self.data) as db, db:
            db.execute("ALTER TABLE opinion_polls DROP COLUMN first_seen")
            db.execute("ALTER TABLE riding_projections DROP COLUMN probs")
            db.execute("DROP TABLE opinion_notes")
        with connect(self.data) as db:
            polls_columns = {row[1] for row in db.execute("PRAGMA table_info(opinion_polls)")}
            riding_columns = {row[1] for row in db.execute("PRAGMA table_info(riding_projections)")}
            self.assertIn("first_seen", polls_columns)
            self.assertIn("probs", riding_columns)
            self.assertEqual(db.execute("SELECT count(*) FROM opinion_polls WHERE first_seen IS NULL").fetchone()[0], 0)
            self.assertEqual(db.execute("SELECT count(*) FROM opinion_polls WHERE first_seen != fetched_at").fetchone()[0], 0)
            self.assertIsNotNone(db.execute("SELECT name FROM sqlite_master WHERE name='opinion_notes'").fetchone())
        self.serve()
        status, body = self.get("/api/polls/ridings")
        self.assertEqual(status, 200)
        self.assertTrue(all(item["win_prob"] is None for item in body["ridings"]))
        self.assertEqual(self.get("/api/polls/summary?history=0")[0], 200)

    def test_16_evening_digest_carries_the_poll_line(self):
        self.setup_data()
        with store.connect(self.data) as db, db:
            for day, lpc, cpc in (("2026-10-08", 199, 99), ("2026-10-09", 201, 98), ("2026-10-10", 201, 98)):
                db.execute("INSERT INTO projections VALUES (?,?)", (day, json.dumps(projection_body(lpc, cpc))))
            polls = [("338:backfill:a", "2026-10-01T12:00:00Z"), ("338:new:b", "2026-10-09T13:00:00Z"),
                     ("338:new:c", "2026-10-09T13:00:00Z")]
            for poll_id, seen in polls:
                db.execute("INSERT INTO opinion_polls (id,region,firm,end_date,sample,rolling,link,lpc,cpc,ndp,gpc,bq,oth,"
                           "fetched_at,first_seen) VALUES (?,'CAN','Firm','2026-10-01',1000,1,'l',40,30,10,5,8,7,?,?)",
                           (poll_id, seen, seen))
            evening = build(db, "2026-10-09", "evening", NOW)
            self.assertEqual(evening["sections"], [])
            self.assertEqual(evening["opinion"], {"kind": "opinion", "text":
                             "2 new polls. Projection: LPC 201 (+2), CPC 98 (-1), NDP 12 (no change)."})
            # No new polls and no follow sections: no digest.
            self.assertIsNone(build(db, "2026-10-10", "evening", NOW))
            # The morning digest never carries the line: with Hansard for the day and no follows it is not built at all.
            db.execute("INSERT INTO documents VALUES ('hansard/45-1/150','hansard','45-1',150,NULL,'2026-10-09','url','now')")
            self.assertIsNone(build(db, "2026-10-09", "morning", NOW))


if __name__ == "__main__":
    unittest.main()
