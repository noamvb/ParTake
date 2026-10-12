from datetime import datetime, timezone
import io
from pathlib import Path
import tempfile
import unittest
import zipfile

from watch.store import connect
from watch.tests.test_opinion_sources import URL_EC, fixture


NOW = datetime(2026, 10, 12, 15, tzinfo=timezone.utc)
HEADER = ",".join("col%d" % i for i in range(18))


def zip_of(number, party="Liberal", elected="N", votes="5"):
    line = [number, "Nowhere", "Nulle part", "1", "Poll", "N", "N", "", "0", "10", "Doe", "", "Jo", party, party,
            "N", elected, votes]
    text = HEADER + "\n" + ",".join(line) + "\n"
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as archive:
        archive.writestr("results.csv", "﻿" + text)
    return buffer.getvalue()


class OpinionResultsTests(unittest.TestCase):
    def test_07_sample_zip(self):
        from watch.opinion.results import parse_results
        ridings, results = parse_results(fixture("ec-ge45-sample.zip"))
        by_id = {riding["id"]: riding for riding in ridings}
        self.assertEqual(len(ridings), 3)
        self.assertEqual(by_id["10001"], {"id": "10001", "name_en": "Avalon", "name_fr": "Avalon",
                                          "province": "NL", "region": "ATL"})
        self.assertEqual(by_id["60001"]["region"], "TERR")
        self.assertEqual(by_id["24001"]["region"], "QC")
        avalon = {row["party"]: row for row in results if row["riding"] == "10001"}
        self.assertEqual(avalon["LPC"]["votes"], 27563)
        self.assertEqual(avalon["CPC"]["votes"], 16953)
        self.assertEqual(avalon["NDP"]["votes"], 2284)
        self.assertEqual(avalon["OTH"]["votes"], 230)
        self.assertNotIn("PPC", avalon)
        self.assertEqual(avalon["LPC"]["elected"], 1)
        self.assertEqual(avalon["CPC"]["elected"], 0)

    def test_08_unknown_province_prefix(self):
        from watch.opinion.results import parse_results
        with self.assertRaises(ValueError):
            parse_results(zip_of("99001"))

    def test_08_ppc_and_elected_flags(self):
        from watch.opinion.results import parse_results
        _ridings, results = parse_results(zip_of("35001", party="People's Party - PPC", elected="Y", votes="7"))
        self.assertEqual(results, [{"riding": "35001", "party": "PPC", "votes": 7, "elected": 1}])

    def test_load_results_skips_download_when_loaded(self):
        from watch.opinion.results import load_results
        calls = []

        def fetch(url):
            calls.append(url)
            return fixture("ec-ge45-sample.zip")

        with tempfile.TemporaryDirectory() as temp:
            data = Path(temp)
            self.assertTrue(load_results(data, fetch, NOW))
            self.assertEqual(calls, [URL_EC])
            self.assertTrue(load_results(data, fetch, NOW))
            self.assertEqual(calls, [URL_EC])
            self.assertTrue(load_results(data, fetch, NOW, force=True))
            self.assertEqual(calls, [URL_EC, URL_EC])
            with connect(data) as db:
                self.assertEqual(db.execute("SELECT count(*) FROM ridings").fetchone()[0], 3)
                self.assertEqual(db.execute("SELECT count(*) FROM riding_results WHERE election='2025'").fetchone()[0],
                                 db.execute("SELECT count(*) FROM riding_results").fetchone()[0])
