"""Back-test: project the 2021 election from the 2021 campaign polls on the 2019 result, and compare with 2021."""

import gzip
import json
from pathlib import Path

from watch.opinion.average import average
from watch.opinion.results import parse_table12
from watch.opinion.sources import parse_338
from watch.opinion.swing import PARTIES, project, region_totals, seats, shares


FIXTURES = Path(__file__).resolve().parents[1] / "tests" / "fixtures"
CAMPAIGN_START, CAMPAIGN_END = "2021-08-15", "2021-09-19"
REGIONS = ("CAN", "ATL", "QC", "ON", "PR", "AB", "BC")


def backtest_2021(polls2_html, table12_2019, table12_2021):
    polls = [poll for poll in parse_338(polls2_html)["polls"] if CAMPAIGN_START <= poll["end_date"] <= CAMPAIGN_END]
    averages = {}
    for region in REGIONS:
        found = average([poll for poll in polls if poll["region"] == region], CAMPAIGN_END)
        if found is not None:
            averages[region] = found["shares"]
    projection = project(table12_2019, averages)
    projected = seats(projection, table12_2019)["CAN"]
    actual_shares = {riding: shares(result["votes"]) for riding, result in table12_2021.items()}
    actual_winner = {riding: max(PARTIES, key=lambda party: values[party]) for riding, values in actual_shares.items()}
    actual = dict.fromkeys(PARTIES, 0)
    for winner in actual_winner.values():
        actual[winner] += 1
    hits = sum(1 for riding, won in projection.items() if won["winner"] == actual_winner[riding])
    national = region_totals(table12_2021)["CAN"]
    return {"projected": projected, "actual": actual, "ridings": len(projection), "hits": hits,
            "hit_rate": hits / len(projection),
            "national_error": {party: averages["CAN"][party] - national[party] for party in PARTIES}}


def main(argv=None):
    def fixture(name):
        return gzip.decompress((FIXTURES / name).read_bytes())

    result = backtest_2021(fixture("338-polls2-2026-10-12.html.gz"), parse_table12(fixture("ec-ge43-table12.csv.gz")),
                           parse_table12(fixture("ec-ge44-table12.csv.gz")))
    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
