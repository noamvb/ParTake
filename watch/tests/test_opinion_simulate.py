import unittest

from watch.opinion.simulate import MAJORITY, simulate
from watch.opinion.swing import PARTIES, project, region_totals


def riding_entry(shares, region="ON"):
    """One riding with the given shares, as swing.project returns them, and its results entry."""
    full = {party: float(shares.get(party, 0)) for party in PARTIES}
    return {"shares": full, "winner": max(PARTIES, key=lambda p: full[p]), "margin": 0.0}, {"region": region, "votes": {}}


def build(riding_list):
    """riding_list: [(id, shares, region)] -> (projection, results) for simulate."""
    projection, results = {}, {}
    for riding_id, shares, region in riding_list:
        projection[riding_id], results[riding_id] = riding_entry(shares, region)
    return projection, results


def sample_projection():
    from watch.opinion.results import parse_results
    from watch.tests.test_opinion_sources import fixture
    ridings, rows = parse_results(fixture("ec-ge45-sample.zip"))
    results = {riding["id"]: dict(region=riding["region"], votes={}) for riding in ridings}
    for row in rows:
        results[row["riding"]]["votes"][row["party"]] = row["votes"]
    return project(results, region_totals(results)), results


class SimulateTests(unittest.TestCase):
    def test_01_fixed_seed_is_deterministic(self):
        projection, results = sample_projection()
        first = simulate(projection, results, runs=500, seed=7)
        self.assertEqual(first, simulate(projection, results, runs=500, seed=7))
        close, close_results = build([("r1", {"LPC": 50, "CPC": 50}, "ON")])
        self.assertNotEqual(simulate(close, close_results, runs=500, seed=7)["ridings"],
                            simulate(close, close_results, runs=500, seed=8)["ridings"])

    def test_02_no_error_gives_the_projected_winner(self):
        projection, results = build([("r1", {"LPC": 60, "CPC": 40}, "ON")])
        found = simulate(projection, results, runs=100, seed=1, sd=(0, 0, 0))
        self.assertEqual(found["ridings"]["r1"], {"LPC": 1.0})
        self.assertEqual(found["seats"]["LPC"]["median"], 1)
        self.assertEqual(found["seats"]["CPC"]["median"], 0)

    def test_03_party_with_zero_share_never_wins(self):
        projection, results = build([("r1", {"LPC": 1, "CPC": 0}, "ON")])
        found = simulate(projection, results, runs=1000, seed=3)
        self.assertNotIn("CPC", found["ridings"]["r1"])
        self.assertEqual(found["ridings"]["r1"], {"LPC": 1.0})
        self.assertEqual(found["seats"]["CPC"], dict(median=0, low=0, high=0))
        # Large errors cannot give a zero party a share: only the two parties with a share can win.
        projection, results = build([("r2", {"LPC": 2, "NDP": 2}, "ON")])
        found = simulate(projection, results, runs=1000, seed=4, sd=(10, 10, 10))
        self.assertTrue(set(found["ridings"]["r2"]) <= {"LPC", "NDP"})

    def test_04_ranges_bracket_the_median_on_the_sample(self):
        projection, results = sample_projection()
        found = simulate(projection, results, runs=2000, seed=2025)
        self.assertEqual(found["runs"], 2000)
        for party in PARTIES:
            stats = found["seats"][party]
            self.assertLessEqual(stats["low"], stats["median"], party)
            self.assertLessEqual(stats["median"], stats["high"], party)
        self.assertEqual(set(found["majority"]), set(PARTIES))
        self.assertEqual(set(found["minority"]), set(PARTIES))

    def test_05_majority_and_minority_odds(self):
        # 343 identical ridings, LPC 60 to CPC 40 with no error: LPC wins them all.
        identical = [("r%03d" % n, {"LPC": 60, "CPC": 40}, "ON") for n in range(343)]
        projection, results = build(identical)
        found = simulate(projection, results, runs=10, seed=5, sd=(0, 0, 0))
        self.assertEqual(MAJORITY, 172)
        self.assertEqual(found["majority"]["LPC"], 1.0)
        self.assertEqual(found["minority"]["LPC"], 0.0)
        # LPC wins 150 ridings, CPC 100 and NDP 93: LPC has the most seats but short of a majority.
        split = ([("a%03d" % n, {"LPC": 60, "CPC": 40}, "ON") for n in range(150)]
                 + [("b%03d" % n, {"CPC": 60, "LPC": 40}, "QC") for n in range(100)]
                 + [("c%03d" % n, {"NDP": 60, "LPC": 40}, "BC") for n in range(93)])
        projection, results = build(split)
        found = simulate(projection, results, runs=10, seed=6, sd=(0, 0, 0))
        self.assertEqual(found["minority"]["LPC"], 1.0)
        self.assertEqual(found["majority"]["LPC"], 0.0)
        self.assertEqual(found["seats"]["LPC"]["median"], 150)


if __name__ == "__main__":
    unittest.main()
