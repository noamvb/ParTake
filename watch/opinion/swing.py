"""Mixed swing per riding: 2025 shares moved by each region's change in the polling average, then seats.

A party that has lost support loses the same fraction of its share in every riding (proportional);
a party that has gained support gains the same number of points in every riding (uniform). Multiplying
gains would blow up small parties in their few strong ridings (a party doubling from 1.5% to 3% would
double a 34% local share).
"""


PARTIES = ("LPC", "CPC", "NDP", "GPC", "BQ", "OTH")


def _tally(votes, counts):
    # Anything that is not a model party (PPC, independents) counts as Others.
    for party, count in votes.items():
        counts[party if party in counts else "OTH"] += count
    return counts


def _percent(counts):
    total = sum(counts.values())
    return {party: 100.0 * counts[party] / total if total else 0.0 for party in PARTIES}


def shares(votes):
    return _percent(_tally(votes, dict.fromkeys(PARTIES, 0)))


def region_totals(results):
    counts = {}
    for riding in results.values():
        for key in (riding["region"], "CAN"):
            _tally(riding["votes"], counts.setdefault(key, dict.fromkeys(PARTIES, 0)))
    return {key: _percent(tally) for key, tally in counts.items()}


def _average_key(region, averages):
    # Territories and regions without a polling average use the national average and base.
    return region if region != "TERR" and region in averages else "CAN"


def _moved(base, average, region):
    if region <= 0:
        return base
    if average < region:
        return base * average / region
    return base + average - region


def project(results, averages):
    totals = region_totals(results)
    projection = {}
    for riding_id, riding in results.items():
        key = _average_key(riding["region"], averages)
        base, average, region = shares(riding["votes"]), averages[key], totals[key]
        scaled = {party: _moved(base[party], average[party], region[party]) for party in PARTIES}
        total = sum(scaled.values())
        if total:
            scaled = {party: 100.0 * value / total for party, value in scaled.items()}
        winner = max(PARTIES, key=lambda party: scaled[party])
        second = sorted(scaled.values(), reverse=True)[1]
        projection[riding_id] = {"shares": scaled, "winner": winner, "margin": scaled[winner] - second}
    return projection


def seats(projection, results):
    regions = {riding["region"] for riding in results.values()}
    counts = {"CAN": dict.fromkeys(PARTIES, 0)}
    counts.update({region: dict.fromkeys(PARTIES, 0) for region in regions})
    for riding_id, won in projection.items():
        counts["CAN"][won["winner"]] += 1
        counts[results[riding_id]["region"]][won["winner"]] += 1
    return counts
