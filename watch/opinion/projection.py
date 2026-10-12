"""Daily seat projection: the polling average on each day since the 2025 election, projected onto every riding."""

import argparse
from datetime import date, datetime, timedelta, timezone
import json
import sys
from zoneinfo import ZoneInfo

from watch.opinion.average import PARTIES, average
from watch.opinion.results import results_from_db
from watch.opinion.swing import project, seats
from watch.store import DEFAULT_DATA, connect, iso, set_meta


OTTAWA = ZoneInfo("America/Toronto")
FIRST_DAY = date(2025, 4, 29)
REGIONS = ("CAN", "ATL", "QC", "ON", "PR", "AB", "BC")


def _polls_by_region(db):
    polls = {}
    for row in db.execute("SELECT * FROM opinion_polls"):
        polls.setdefault(row["region"], []).append(dict(
            firm=row["firm"], end_date=row["end_date"], sample=row["sample"], rolling=row["rolling"],
            shares={party: row[party.lower()] for party in PARTIES}))
    return polls


def recompute(data_dir, now):
    """Rewrite the projection for every day from the first day with polls to today (Ottawa); returns days written."""
    with connect(data_dir) as db:
        results = results_from_db(db)
        if not results:
            return 0
        polls = _polls_by_region(db)
    today = now.astimezone(OTTAWA).date()
    projections, ridings = [], []
    day = FIRST_DAY
    while day <= today:
        as_of = day.isoformat()
        averages = {}
        for region in REGIONS:
            found = average(polls.get(region, []), as_of)
            if found is not None:
                averages[region] = found
        if "CAN" in averages:
            shares = {region: found["shares"] for region, found in averages.items()}
            projection = project(results, shares)
            counts = seats(projection, results)
            body = dict(average=shares, polls_used=averages["CAN"]["polls_used"], seats=counts)
            projections.append((as_of, json.dumps(body)))
            ridings.extend((riding, as_of, json.dumps(won["shares"]), won["winner"], won["margin"])
                           for riding, won in projection.items())
        day += timedelta(days=1)
    with connect(data_dir) as db, db:
        db.execute("BEGIN IMMEDIATE")
        db.executemany("INSERT INTO projections VALUES (?,?) ON CONFLICT(date) DO UPDATE SET body=excluded.body",
                       projections)
        db.executemany("INSERT INTO riding_projections VALUES (?,?,?,?,?) ON CONFLICT(riding, date) DO UPDATE SET "
                       "shares=excluded.shares, winner=excluded.winner, margin=excluded.margin", ridings)
        set_meta(db, "opinion:projected_at", iso(now))
    return len(projections)


def main(argv=None):
    parser = argparse.ArgumentParser(description="Recompute the daily seat projection from the polls")
    parser.add_argument("--data", default=DEFAULT_DATA)
    args = parser.parse_args(argv)
    days = recompute(args.data, datetime.now(timezone.utc))
    sys.stderr.write("projection %d days\n" % days)
    return 0


if __name__ == "__main__":
    sys.exit(main())
