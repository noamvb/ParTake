"""Polling average for one region on one day: each firm's latest poll, weighted by sample, age and independence."""

from datetime import date
import math


PARTIES = ("LPC", "CPC", "NDP", "GPC", "BQ", "OTH")


def _model_shares(shares):
    # PPC is not a model party: it counts as Others.
    folded = {party: float(shares.get(party, 0)) for party in PARTIES}
    folded["OTH"] += float(shares.get("PPC", 0))
    return folded


def average(polls, as_of, max_age=60, half_life=14):
    today = date.fromisoformat(as_of)
    latest = {}
    for poll in polls:
        end = date.fromisoformat(poll["end_date"])
        age = (today - end).days
        if end > today or age > max_age:
            continue
        shares = _model_shares(poll["shares"])
        total = sum(shares.values())
        if total <= 0:
            continue
        if poll["firm"] not in latest or end > latest[poll["firm"]][0]:
            latest[poll["firm"]] = (end, age, poll["sample"], poll["rolling"], shares, total)
    if not latest:
        return None
    sums = dict.fromkeys(PARTIES, 0.0)
    weights = 0.0
    for _end, age, sample, rolling, shares, total in latest.values():
        weight = math.sqrt(sample if sample else 1000) * 0.5 ** (age / half_life) * rolling
        weights += weight
        for party in PARTIES:
            sums[party] += weight * shares[party] * 100 / total
    if weights <= 0:
        return None
    return {"shares": {party: sums[party] / weights for party in PARTIES}, "polls_used": len(latest)}
