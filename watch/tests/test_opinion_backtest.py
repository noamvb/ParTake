import unittest

from watch.opinion.backtest import backtest_2021
from watch.opinion.results import parse_table12
from watch.opinion.sources import parse_338
from watch.tests.test_opinion_sources import fixture


def polls2():
    return parse_338(fixture("338-polls2-2026-10-12.html.gz"))


class OpinionBacktestTests(unittest.TestCase):
    def test_09_polls2_campaign_window(self):
        polls = polls2()["polls"]
        window = [poll for poll in polls if poll["region"] == "CAN" and "2021-08-15" <= poll["end_date"] <= "2021-09-19"]
        self.assertEqual(len(window), 141)
        self.assertTrue(all("PPC" in poll["shares"] for poll in polls))

    def test_10_backtest_2021_numbers(self):
        result = backtest_2021(fixture("338-polls2-2026-10-12.html.gz"),
                               parse_table12(fixture("ec-ge43-table12.csv.gz")),
                               parse_table12(fixture("ec-ge44-table12.csv.gz")))
        self.assertEqual(result["ridings"], 338)
        self.assertEqual(sum(result["projected"].values()), 338)
        self.assertEqual(sum(result["actual"].values()), 338)
        self.assertGreaterEqual(result["hit_rate"], 0.80)
        # Pinned from the 12 Oct 2026 run (mixed swing); the model is not tuned to the result.
        self.assertEqual(result["projected"], {"LPC": 152, "CPC": 121, "NDP": 33, "GPC": 1, "BQ": 30, "OTH": 1})
        self.assertEqual(result["actual"], {"LPC": 160, "CPC": 119, "NDP": 25, "GPC": 2, "BQ": 32, "OTH": 0})
        self.assertEqual(result["hits"], 308)
        self.assertAlmostEqual(result["hit_rate"], 308 / 338, places=12)

    def test_11_liberal_and_conservative_within_25_seats(self):
        result = backtest_2021(fixture("338-polls2-2026-10-12.html.gz"),
                               parse_table12(fixture("ec-ge43-table12.csv.gz")),
                               parse_table12(fixture("ec-ge44-table12.csv.gz")))
        for party in ("LPC", "CPC"):
            self.assertLessEqual(abs(result["projected"][party] - result["actual"][party]), 25, party)
