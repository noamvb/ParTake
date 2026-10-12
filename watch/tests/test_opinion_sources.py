from datetime import datetime, timezone
import gzip
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from urllib.error import HTTPError

from watch.store import connect


FIXTURES = Path(__file__).parent / "fixtures"
NOW = datetime(2026, 10, 12, 15, tzinfo=timezone.utc)
URL_338 = "https://338canada.com/polls.htm"
WIKI = "https://en.wikipedia.org/w/api.php?action=parse&page=Opinion_polling_for_the_46th_Canadian_federal_election"
URL_EC = "https://elections.ca/res/rep/off/ovrGE45/62/data_donnees/pollresults_resultatsbureauCanada.zip"
SECTIONS = json.dumps({"parse": {"sections": [{"line": "Leadership polls", "index": "14"},
                                              {"line": "Government approval polls", "index": "19"}]}}).encode()
REGIONS = ("National", "ATL", "QC", "ON", "PR", "AB", "BC")


def fixture(name):
    body = (FIXTURES / name).read_bytes()
    return gzip.decompress(body) if name.endswith(".gz") else body


def live_pages():
    return {URL_338: fixture("338-polls-2026-10-12.html.gz"),
            WIKI + "&prop=sections&format=json": SECTIONS,
            WIKI + "&prop=text&section=14&format=json&formatversion=2": fixture("wiki-46-section14.json.gz"),
            WIKI + "&prop=text&section=19&format=json&formatversion=2": fixture("wiki-46-section19.json.gz"),
            URL_EC: fixture("ec-ge45-sample.zip")}


def page(rows):
    """A 338 page with the given national rows; the other regions are empty."""
    demos = {name: {"title": name, "rows": rows if name == "National" else []} for name in REGIONS}
    return ("<script>window.demopoll_TABLE_DATA = " + json.dumps({"demos": demos}) + ";</script>").encode()


def row(firm="Test Firm", date="2026-10-01", leader="L +21", labels=("49", "28", "11", "3", "6"),
        generalelx="", sample="1,000", rolling=""):
    return {"generalelx": generalelx, "firm": firm, "date": date, "sample": sample, "isRolling": rolling,
            "poll_link": "https://example.com/poll.pdf", "leader": leader,
            "cells": [{"label": label} for label in labels]}


class OpinionSourceTests(unittest.TestCase):
    def test_01_338_fixture(self):
        from watch.opinion.sources import parse_338
        parsed = parse_338(fixture("338-polls-2026-10-12.html.gz"))
        polls = parsed["polls"]
        self.assertIsInstance(parsed["skipped"], int)
        self.assertEqual(parsed["skipped"], 0)
        by_region = {}
        for poll in polls:
            by_region.setdefault(poll["region"], []).append(poll)
        self.assertEqual(len(by_region["CAN"]), 230 - parsed["skipped"])
        self.assertTrue({"CAN", "ATL", "QC", "ON", "PR", "AB", "BC"} <= set(by_region))
        self.assertEqual(by_region["CAN"][0], {
            "id": "338:2026-10-02:nanos-research", "firm": "Nanos Research", "end_date": "2026-10-02",
            "sample": 1020, "rolling": 0.25,
            "link": "https://nanos.co/wp-content/uploads/2026/10/Political-PackagexY9687-2026-10-02-FOR-RELEASE.pdf",
            "region": "CAN", "shares": {"LPC": 49, "CPC": 28, "NDP": 11, "GPC": 3, "BQ": 6, "OTH": 3}})

    def test_02_shares_and_ids(self):
        from watch.opinion.sources import parse_338
        polls = parse_338(fixture("338-polls-2026-10-12.html.gz"))["polls"]
        exact = 0
        for poll in polls:
            total = sum(poll["shares"].values())
            labels = total - poll["shares"]["OTH"]
            if labels <= 100:
                # OTH = 100 - the party labels, so the total is 100 whenever the labels fit.
                self.assertEqual(total, 100, poll["id"])
                exact += 1
            else:
                # Rounded labels above 100 floor OTH at 0 (17 such polls in the 2026-10-12 page, at most 107).
                self.assertEqual(poll["shares"]["OTH"], 0, poll["id"])
                self.assertLessEqual(total, 107, poll["id"])
        self.assertGreater(exact, 200)
        keys = [(poll["region"], poll["id"]) for poll in polls]
        self.assertEqual(len(keys), len(set(keys)))

    def test_03_leader_margin_mismatch_is_skipped(self):
        from watch.opinion.sources import parse_338
        parsed = parse_338(page([row(firm="Bad Margin", leader="L +5"), row(firm="Good", leader="L +22",
                                                                          labels=("50", "28", "11", "3", "6"))]))
        self.assertEqual(parsed["skipped"], 1)
        self.assertEqual([poll["firm"] for poll in parsed["polls"] if poll["region"] == "CAN"], ["Good"])

    def test_04_rolling_and_blank_labels(self):
        from watch.opinion.sources import parse_338
        parsed = parse_338(page([row(rolling=""), row(firm="Half", date="2026-09-30", rolling="<sup>(1/2)</sup>",
                                                      leader="L +5", labels=("49", "44", "", "", "")),
                                 row(firm="Tie", date="2026-09-29", leader="Tie", labels=("30", "30", "", "", "")),
                                 row(firm="Election", generalelx="header2", date="2025-04-28")]))
        polls = {poll["firm"]: poll for poll in parsed["polls"] if poll["region"] == "CAN"}
        self.assertEqual(polls["Test Firm"]["rolling"], 1.0)
        self.assertEqual(polls["Half"]["rolling"], 0.5)
        self.assertEqual(polls["Half"]["shares"], {"LPC": 49, "CPC": 44, "NDP": 0, "GPC": 0, "BQ": 0, "OTH": 7})
        self.assertEqual(polls["Tie"]["shares"]["NDP"], 0)
        self.assertNotIn("Election", polls)
        self.assertEqual(parsed["skipped"], 0)

    def test_05_duplicate_ids_get_suffixes(self):
        from watch.opinion.sources import parse_338
        parsed = parse_338(page([row(firm="Same Firm!"), row(firm="same firm"), row(firm="Same-Firm")]))
        ids = [poll["id"] for poll in parsed["polls"] if poll["region"] == "CAN"]
        self.assertEqual(ids, ["338:2026-10-01:same-firm", "338:2026-10-01:same-firm-2", "338:2026-10-01:same-firm-3"])

    def test_06_best_pm_fixture(self):
        from watch.opinion.sources import parse_best_pm
        rows = parse_best_pm(fixture("wiki-46-section14.json.gz"))
        self.assertEqual(rows[0]["firm"], "Nanos Research")
        self.assertEqual(rows[0]["end_date"], "2026-10-02")
        self.assertEqual(rows[0]["shares"]["Mark Carney"], 59.2)
        self.assertEqual(rows[0]["shares"]["Pierre Poilievre"], 20.4)
        keys = {name for row_ in rows for name in row_["shares"]}
        self.assertFalse([name for name in keys if name.startswith("Unsure")])
        self.assertNotIn("Lead", keys)
        self.assertNotIn("Polling firm", keys)
        dates = [row_["end_date"] for row_ in rows]
        self.assertEqual(dates, sorted(dates, reverse=True))

    def test_07_approval_fixture(self):
        from watch.opinion.sources import parse_approval
        rows = parse_approval(fixture("wiki-46-section19.json.gz"))
        self.assertGreaterEqual(len(rows), 1)
        for row_ in rows:
            self.assertIsInstance(row_["approve"], float)
            self.assertIsInstance(row_["disapprove"], float)
            self.assertTrue(0 <= row_["approve"] <= 100)
            self.assertTrue(0 <= row_["disapprove"] <= 100)
        # Read by hand from the fixture: Liaison Strategies, "October 3, 2026", 66% approve, 27% disapprove.
        self.assertEqual(rows[0], {"firm": "Liaison Strategies", "end_date": "2026-10-03",
                                   "approve": 66.0, "disapprove": 27.0})

    def test_09_poll_opinion_fills_tables_and_is_repeatable(self):
        from watch.opinion.sources import parse_338, poll_opinion
        pages = live_pages()
        with tempfile.TemporaryDirectory() as temp:
            data = Path(temp)
            calls = []

            def fetch(url):
                calls.append(url)
                if url not in pages:
                    raise HTTPError(url, 404, "not found", None, None)
                return pages[url]

            self.assertTrue(poll_opinion(data, fetch, NOW))
            counts = self.counts(data)
            self.assertEqual(counts["polls"], len(parse_338(pages[URL_338])["polls"]))
            self.assertEqual((counts["best"], counts["approval"], counts["ridings"]), (72, 103, 3))
            self.assertGreater(counts["results"], 3)
            self.assertTrue(self.status(data)["ok"])
            with connect(data) as db:
                self.assertEqual(db.execute("SELECT value FROM meta WHERE key='opinion:fetched_at'").fetchone()[0],
                                 "2026-10-12T15:00:00Z")
                self.assertEqual(db.execute("SELECT count(*) FROM opinion_polls WHERE region='CAN'").fetchone()[0], 230)
            before = counts
            self.assertTrue(poll_opinion(data, fetch, NOW))
            self.assertEqual(self.counts(data), before)

    def test_10_wikipedia_failure_keeps_338(self):
        from watch.opinion.sources import poll_opinion
        pages = {url: body for url, body in live_pages().items() if url.startswith(URL_338) or url == URL_EC}

        def fetch(url):
            if url not in pages:
                raise HTTPError(url, 403, "forbidden", None, None)
            return pages[url]

        with tempfile.TemporaryDirectory() as temp:
            data = Path(temp)
            self.assertFalse(poll_opinion(data, fetch, NOW))
            with connect(data) as db:
                self.assertEqual(db.execute("SELECT count(*) FROM opinion_polls WHERE region='CAN'").fetchone()[0], 230)
                self.assertEqual(db.execute("SELECT count(*) FROM leader_polls").fetchone()[0], 0)
            status = self.status(data)
            self.assertFalse(status["ok"])
            self.assertIn("wikipedia", status["error"])

    def test_12_cli_accepts_opinion_source(self):
        from watch.poll import main
        with tempfile.TemporaryDirectory() as temp, \
                patch("watch.opinion.sources.poll_opinion", return_value=True) as poll:
            self.assertEqual(main(["--data", temp, "--sources", "opinion"]), 0)
            self.assertEqual(poll.call_args.args[0], temp)
            self.assertEqual(poll.call_count, 1)

    def counts(self, data):
        with connect(data) as db:
            return {"polls": db.execute("SELECT count(*) FROM opinion_polls").fetchone()[0],
                    "best": db.execute("SELECT count(*) FROM leader_polls WHERE kind='best_pm'").fetchone()[0],
                    "approval": db.execute("SELECT count(*) FROM leader_polls WHERE kind='approval'").fetchone()[0],
                    "ridings": db.execute("SELECT count(*) FROM ridings").fetchone()[0],
                    "results": db.execute("SELECT count(*) FROM riding_results").fetchone()[0]}

    def status(self, data):
        with connect(data) as db:
            return json.loads(db.execute("SELECT value FROM meta WHERE key='source:opinion'").fetchone()[0])
