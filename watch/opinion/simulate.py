"""Simulations of the seat projection: seat ranges, majority and minority odds, and per-riding win probabilities."""

import random

from watch.opinion.swing import PARTIES


MAJORITY = 172


def simulate(projection, results, runs=10000, seed=0, sd=(2.0, 3.0, 5.0)):
    """Add national, regional and riding errors to every projected share, run the seat count, and count the outcomes."""
    rng = random.Random(seed)
    ridings = sorted(projection)
    regions = sorted({results[riding]["region"] for riding in ridings})
    # Only parties with a projected share above zero get errors, so a party at zero stays at zero and never wins.
    contests = []
    for riding in ridings:
        shares = projection[riding]["shares"]
        entries = [(i, shares[party]) for i, party in enumerate(PARTIES) if shares[party] > 0]
        contests.append((riding, results[riding]["region"], entries))
    seat_runs = [[] for _ in PARTIES]
    majority_runs = [0] * len(PARTIES)
    minority_runs = [0] * len(PARTIES)
    riding_wins = [[0] * len(PARTIES) for _ in contests]
    for _ in range(runs):
        national = [rng.gauss(0, sd[0]) for _ in PARTIES]
        regional = {region: [rng.gauss(0, sd[1]) for _ in PARTIES] for region in regions}
        seats = [0] * len(PARTIES)
        for k, (_riding, region, entries) in enumerate(contests):
            error = regional[region]
            winner, best = None, -1.0
            for i, share in entries:
                value = max(0.0, share + national[i] + error[i] + rng.gauss(0, sd[2]))
                if value > best:
                    winner, best = i, value
            if winner is not None:
                seats[winner] += 1
                riding_wins[k][winner] += 1
        for i, count in enumerate(seats):
            seat_runs[i].append(count)
            if count >= MAJORITY:
                majority_runs[i] += 1
        top = max(seats)
        leaders = [i for i, count in enumerate(seats) if count == top]
        if len(leaders) == 1 and top < MAJORITY:
            minority_runs[leaders[0]] += 1
    n = runs
    seat_stats, majority, minority = {}, {}, {}
    for i, party in enumerate(PARTIES):
        counts = sorted(seat_runs[i])
        seat_stats[party] = dict(median=counts[(n - 1) // 2], low=counts[int(0.1 * (n - 1))],
                                 high=counts[int(0.9 * (n - 1))])
        majority[party] = majority_runs[i] / n
        minority[party] = minority_runs[i] / n
    win_prob = {}
    for k, (riding, _region, _entries) in enumerate(contests):
        win_prob[riding] = {party: riding_wins[k][i] / n for i, party in enumerate(PARTIES) if riding_wins[k][i] > 0}
    return {"runs": n, "seats": seat_stats, "majority": majority, "minority": minority, "ridings": win_prob}
