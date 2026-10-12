# Polls HTTP API - contract between the Deck service and ParTake

Draft, 12 Oct 2026, part of [PLAN.md](PLAN.md). Served by the watch API
process; same conventions as [../watch/api.md](../watch/api.md) (JSON, ISO
8601 UTC, Ottawa dates, errors, `/watch/api/...` through the Deck proxy).
All endpoints are reads; no token. Values in the examples are illustrative.

Parties are `LPC`, `CPC`, `NDP`, `GPC`, `BQ`, `OTH`. Regions are `ATL`, `QC`,
`ON`, `PR`, `AB`, `BC`, `TERR`, plus `CAN` for national. Shares are percents
with one decimal. Riding ids are Elections Canada district numbers as
strings (`"24038"`).

## GET /api/polls/list (P1)

Newest first, paged (`limit`, `before`, `next`). `region` filter (default
`CAN`).

```json
{"polls": [{"id": "338:2026-10-02:nanos-research", "firm": "Nanos Research",
  "end_date": "2026-10-02", "sample": 1020, "rolling": 0.25,
  "link": "https://nanos.co/...pdf", "region": "CAN",
  "shares": {"LPC": 49, "CPC": 28, "NDP": 11, "GPC": 3, "BQ": 6, "OTH": 3}}],
 "next": null,
 "source": {"name": "338Canada", "url": "https://338canada.com/polls.htm", "fetched_at": "2026-10-12T10:30:00Z"}}
```

`rolling` is the independent fraction (1.0 for a one-off poll). The election
row is not a poll and is not listed.

## GET /api/polls/leaders (P1)

```json
{"best_pm": [{"firm": "Abacus Data", "end_date": "2026-10-01",
   "shares": {"Carney": 46, "Poilievre": 31}}],
 "approval": [{"firm": "Angus Reid", "end_date": "2026-09-28", "approve": 55, "disapprove": 38}],
 "source": {"name": "Wikipedia", "url": "https://en.wikipedia.org/wiki/Opinion_polling_for_the_46th_Canadian_federal_election",
   "licence": "CC BY-SA 4.0", "fetched_at": "2026-10-12T10:30:00Z"}}
```

Leader names are the column headers as Wikipedia gives them.

## GET /api/polls/summary (P2; odds fields P3)

```json
{"as_of": "2026-10-12", "polls_used": 14,
 "average": {"CAN": {"LPC": 47.2, "CPC": 29.1, "NDP": 10.4, "GPC": 3.1, "BQ": 6.8, "OTH": 3.4}, "QC": {}},
 "seats": {"LPC": {"median": 201, "low": 188, "high": 214}, "CPC": {}},
 "majority": {"LPC": 0.91, "CPC": 0.0}, "minority": {"LPC": 0.08},
 "seats_total": 343, "majority_line": 172,
 "comparison": {"name": "338Canada", "seats": {"LPC": 205, "CPC": 104}, "as_of": "2026-10-11"},
 "history": [{"date": "2026-10-11", "average": {"LPC": 47.0}, "seats": {"LPC": 199}}],
 "note": {"week_of": "2026-10-05", "text": "Liberals up 1.1 points ..."}}
```

`seats` holds the simulation's median and 10th/90th percentiles (10,000
runs of the latest day, seeded by the date). `majority` and `minority` are
each party's share of runs with 172+ seats, or the most seats short of 172.
They are `null` only if the simulation has not run. `history` has one entry per day since 2025-04-28
(`?history=0` drops it). `comparison` is `null` when 338's number could not
be read.

## GET /api/polls/ridings (P2)

All 343, sorted by riding name. `?mp=<PersonId>` returns the one riding that
MP holds.

```json
{"ridings": [{"id": "24038", "name": "Chicoutimi—Le Fjord", "province": "QC",
  "region": "QC", "mp": {"person_id": "123447", "name": "Daniel Gobeil", "party": "LPC"},
  "won_2025": "CPC", "projected": "LPC", "win_prob": 0.64,
  "status": "at_risk"}]}
```

`status` is from the holder's view: `safe` (holder's party win_prob >= 0.9),
`likely` (>= 0.7), `at_risk` (< 0.7), `projected_loss` (another party is
projected to win). `win_prob` is the projected winner's share of runs. If a
day has no simulation, `win_prob` is `null` and `status` uses the margin
instead: `safe` > 10 points, `likely` > 5, `at_risk` > 0.

## GET /api/polls/ridings/{id} (P2)

One riding: the list fields plus `results_2025` (`{"LPC": 38.2, ...}`),
`projection` (shares), `probs` (each party's win share of runs, or `null`),
and `history` (date, projected shares) since
2025-04-28.

## Digest line (P3)

An evening digest gets an `opinion` key when a national poll was first
seen that day (polls loaded by the first backfill never count):
`"opinion": {"kind": "opinion", "text": "2 new polls. Projection: LPC 201 (+2), CPC 98 (-1)."}`.
It lists parties projected to 10+ seats, with the change from the day
before. A day with no followed activity but a new poll still gets an
evening digest with empty `sections` (see watch api.md "Digests").
