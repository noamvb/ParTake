import unittest

from watch.opinion.average import average
from watch.opinion.results import parse_results, parse_table12
from watch.opinion.swing import PARTIES, project, region_totals, seats
from watch.tests.test_opinion_sources import fixture


def poll(firm, end, lpc, cpc, sample=1000, rolling=1.0, rest=None):
    shares = {"LPC": lpc, "CPC": cpc, "NDP": 0, "GPC": 0, "BQ": 0, "OTH": 100 - lpc - cpc}
    shares.update(rest or {})
    return dict(firm=firm, end_date=end, sample=sample, rolling=rolling, shares=shares)


def shares(**values):
    return {party: values.get(party, 0) for party in PARTIES}


def sample_results():
    ridings, rows = parse_results(fixture("ec-ge45-sample.zip"))
    regions = {riding["id"]: riding["region"] for riding in ridings}
    results = {}
    for row in rows:
        riding = results.setdefault(row["riding"], dict(region=regions[row["riding"]], votes={}))
        riding["votes"][row["party"]] = row["votes"]
    return results


class OpinionModelTests(unittest.TestCase):
    def test_01_latest_poll_per_firm(self):
        polls = [poll("Firm", "2026-10-01", 40, 60), poll("Firm", "2026-10-10", 50, 50)]
        result = average(polls, "2026-10-12")
        self.assertEqual(result["polls_used"], 1)
        self.assertAlmostEqual(result["shares"]["LPC"], 50, places=9)
        self.assertAlmostEqual(result["shares"]["CPC"], 50, places=9)

    def test_02_weights_by_age(self):
        polls = [poll("A", "2026-10-12", 40, 60), poll("B", "2026-09-28", 50, 50)]
        result = average(polls, "2026-10-12")
        self.assertEqual(result["polls_used"], 2)
        self.assertAlmostEqual(result["shares"]["LPC"], (40 * 1 + 50 * 0.5) / 1.5, places=9)

    def test_03_rescale_age_and_empty(self):
        rescaled = average([poll("A", "2026-10-10", 50, 40, rest={"NDP": 10, "GPC": 3, "BQ": 4, "OTH": 0})], "2026-10-12")
        self.assertAlmostEqual(rescaled["shares"]["LPC"], 50 * 100 / 107, places=9)
        self.assertAlmostEqual(sum(rescaled["shares"].values()), 100, places=9)
        old = average([poll("Old", "2026-08-01", 99, 1), poll("New", "2026-10-10", 30, 70)], "2026-10-12")
        self.assertEqual(old["polls_used"], 1)
        self.assertAlmostEqual(old["shares"]["LPC"], 30, places=9)
        self.assertIsNone(average([poll("Old", "2026-08-01", 99, 1)], "2026-10-12"))
        self.assertIsNone(average([poll("Future", "2026-10-13", 99, 1)], "2026-10-12"))
        self.assertIsNone(average([], "2026-10-12"))

    def test_04_proportional_swing_and_rescale(self):
        results = {"1": dict(region="QC", votes={"LPC": 50, "CPC": 50}),
                   "2": dict(region="QC", votes={"LPC": 30, "CPC": 70})}
        averages = {"QC": shares(LPC=50, CPC=50)}
        won = project(results, averages)["1"]
        self.assertAlmostEqual(won["shares"]["LPC"], 60, places=9)
        self.assertAlmostEqual(won["shares"]["CPC"], 40, places=9)
        self.assertEqual(won["winner"], "LPC")
        self.assertAlmostEqual(won["margin"], 20, places=9)

    def test_05_multiplier_is_capped(self):
        results = {"1": dict(region="QC", votes={"LPC": 99, "GPC": 1}),
                   "2": dict(region="QC", votes={"LPC": 99, "GPC": 1})}
        won = project(results, {"QC": shares(LPC=90, GPC=10)})["1"]
        # GPC multiplier is min(3, 10 / 1) = 3, LPC is 90 / 99; uncapped GPC would be 10 and the riding 10 / 100.
        self.assertAlmostEqual(won["shares"]["GPC"], 300 / 93, places=9)
        self.assertAlmostEqual(won["shares"]["LPC"], 100 - 300 / 93, places=9)

    def test_06_territories_use_national_average_and_base(self):
        results = {"1": dict(region="TERR", votes={"LPC": 60, "CPC": 40}),
                   "2": dict(region="QC", votes={"LPC": 40, "CPC": 60})}
        averages = {"CAN": shares(LPC=50, CPC=50), "TERR": shares(LPC=30, CPC=70)}
        won = project(results, averages)["1"]
        self.assertAlmostEqual(won["shares"]["LPC"], 60, places=9)
        self.assertAlmostEqual(won["shares"]["CPC"], 40, places=9)

    def test_07_region_totals_on_sample(self):
        results = sample_results()
        totals = region_totals(results)
        self.assertEqual(results["10001"]["region"], "ATL")
        for region in ("ATL", "QC", "TERR", "CAN"):
            self.assertAlmostEqual(sum(totals[region].values()), 100, places=9)
            self.assertEqual(set(totals[region]), set(PARTIES))
        avalon = results["10001"]["votes"]
        self.assertAlmostEqual(totals["ATL"]["LPC"], 100 * avalon["LPC"] / sum(avalon.values()), places=9)
        ppc = {"x": dict(region="ATL", votes={"PPC": 50, "LPC": 50})}
        self.assertEqual(region_totals(ppc)["ATL"], shares(LPC=50, OTH=50))

    def test_08_table12_winners(self):
        expected = {"ec-ge43-table12.csv.gz": dict(LPC=157, CPC=121, BQ=32, NDP=24, GPC=3, OTH=1),
                    "ec-ge44-table12.csv.gz": dict(LPC=160, CPC=119, BQ=32, NDP=25, GPC=2)}
        for name, winners in expected.items():
            ridings = parse_table12(fixture(name))
            self.assertEqual(len(ridings), 338, name)
            count = dict.fromkeys(PARTIES, 0)
            for riding in ridings.values():
                count[max(riding["votes"], key=riding["votes"].get)] += 1
            self.assertEqual({party: n for party, n in count.items() if n}, winners, name)
