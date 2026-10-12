# Polls: plan

Status: **approved by the owner, 12 Oct 2026** (grilling session). Facts come
from [research/sources.md](research/sources.md) (agy run
`20261012-005720-agy-1853930`, spot-checked the same day). Anything marked
**verify** has not been measured yet. The app/service contract is
[api.md](api.md).

## What it is

Federal opinion polls since the 28 April 2025 election, turned into a seat
projection, in a new **Polls** tab in ParTake (Android + web). The data side
runs inside the Parliament watch service on the Deck (`watch/`), so it reuses
its store, API process, digest and members index.

## Decisions (owner, 12 Oct 2026)

| Question | Decision |
|---|---|
| Which polls | Federal opinion polls only (voting intention), plus leader and government approval polls |
| Goal | Seat projection; a proven simple method, not a modelling project |
| Model | Regional proportional swing first; simulations for ranges and odds second |
| Where | New Polls tab in the bottom bar |
| Top of the tab | Seats per party with a range, majority/minority odds; then the polling-average chart, the leader chart, the latest polls |
| Ridings | Every riding has a page (2025 result, projected winner, odds); MPs followed in Watch show safe / at risk |
| Analysis | Weekly what-changed note, written by fixed rules from the numbers (no LLM) |
| Alerts | None new; new polls and projection changes add a line to the evening digest |
| History | Since 28 April 2025 |
| Check | Back-test on the 2025 election; show 338Canada's seat total beside ours |
| Regional source | Read 338Canada's poll page once a day for private use (owner's choice; no permission asked) |
| Order | Polls now; watch Phase 3 waits |

## Sources

| Data | Source | Notes |
|---|---|---|
| Voting intention, national + 6 regions | `https://338canada.com/polls.htm`, inline `window.demopoll_TABLE_DATA` | `demos` keys `National`, `ATL`, `QC`, `ON`, `PR` (MB/SK), `AB`, `BC`; 149-231 rows each, 2025-04-28 (the election row, `generalelx` set) to now. Row: `firm`, `date` (last field date), `sample` ("1,020"), `isRolling` (`<sup>(1/4)</sup>` = independent fraction), `poll_link`, `leader` ("L +21"), `cells` (5 labels, fixed order **LPC, CPC, NDP, GPC, BQ**; Others = 100 - sum). Party is by position: text colours change with the leader. Check each row: the `leader` margin equals the top two cells' difference. Three rows sum over 101 (source typos, e.g. QC Synopsis Recherche 2026-06-07 = 107); the average rescales each poll to 100. Mod_Security answers 406 to a bare `Mozilla/5.0` agent; watch's `USER_AGENT` gets 200. |
| 338Canada's own seat projection | same site, `window.demopoll_DATA` / projection pages | For the comparison only. Exact field **verify** in P2. |
| Leader + approval polls | Wikipedia `Opinion_polling_for_the_46th_Canadian_federal_election`, sections "Leadership polls" and "Government approval polls", MediaWiki `action=parse` HTML | CC BY-SA 4.0: show the source link and licence on the chart. Needs a `User-Agent` (403 without). |
| 2025 riding results | Elections Canada `pollresults_resultatsbureauCanada.zip` (Format 2, long) under `elections.ca/res/rep/off/ovrGE45/62/data_donnees/` | 343 ridings; the map has not changed since. Sum polls to riding level once; keep the zip in `raw/`. |
| Current MP per riding | watch `members` table | One seat changed in a by-election (Chicoutimi—Le Fjord, CPC to LPC, 31 Aug 2026). Baseline votes stay the 2025 general; the holder comes from `members`. |
| Back-test inputs | Polls: `https://338canada.com/polls2.htm` (same `demopoll_TABLE_DATA` shape, 6 cells per row with PPC, 2015-10-19 to 2025-04-28; 154 national campaign polls 23 Mar-27 Apr 2025, 89-120 per region). Baseline: 2021 results on the 2023 map (Elections Canada transposition) | Polls checked 12 Oct 2026. The transposed baseline was not found on 12 Oct: P2 looks once more, else back-tests 2021 from the 2019 result (same 338-riding map, no transposition needed). |

CBC's Poll Tracker feed is not used: CBC's terms forbid automated scraping.

## Model (the CBC Poll Tracker method, simplified)

1. **Polling average** per region, per day: each pollster's latest poll only
   (so daily trackers count once), weight = `sqrt(sample) x 0.5^(age_days / 14)`
   x the rolling independent fraction. Ignore polls older than 60 days.
   Others = 100 - named parties.
2. **Swing** per riding: `share_new = share_2025 x avg_region / result_region_2025`,
   then rescale the riding to 100. Region of a riding by province:
   NL/PE/NS/NB -> ATL, QC, ON, MB/SK -> PR, AB, BC; the 3 territories use the
   national average. PPC and independents sit in Others.
3. **Seats**: winner = top share. Sum per party per region and nationally.
4. **Simulations** (P3): 10,000 runs per daily update; each run adds a shared
   national error, a regional error and a riding error to every party
   (standard deviations calibrated on the back-test, start at 2.0 / 3.0 / 5.0
   points), rescales and counts seats. Output: median and 80% range per
   party, P(majority) per party (172 of 343), P(minority win), per-riding win
   probability. Seeded, so a rerun gives the same numbers.
5. **Back-test** (P2): run steps 1-3 on the polls up to 27 April 2025 with the
   2021-transposed baseline; report seats vs actual and riding hit rate.
   Kept as a test with the numbers pinned.

Pure functions over stored data, like the rest of watch: a model change is a
rerun of the history.

## Shape

```
watch/opinion/              Python stdlib, same rules as watch/
  sources.py                fetch + parse 338 polls page, Wikipedia leader tables
  results.py                Elections Canada 2025 zip -> riding baseline (+ 2021 transposed for the back-test)
  average.py                polling average per region per day
  swing.py                  proportional swing, seat counts
  simulate.py               simulations, odds (P3)
  notes.py                  weekly what-changed note + digest line (P3)
  backtest.py               2025 back-test (P2)
watch.db tables             opinion_polls, opinion_shares, leader_polls, ridings,
                            riding_results, projections (one row per day), riding_projections, opinion_notes
lib/polls/                  app: client + models for /api/polls/*
lib/ui/polls_screen.dart    the Polls tab; riding page; charts
```

- Fetch once a day at 06:30 Ottawa (338 updates overnight) inside the
  existing `partake-watch-poller`; recompute the projection when the poll
  set changed. Raw pages go to `raw/opinion/` only when the hash changed.
- Backfill: one run over the whole 338 table (it already holds every poll
  since the election) gives the history; the projection is recomputed for
  every day since 2025-04-28.
- The app reads the API through the Deck proxy like the Watch tab; no
  Android background work.
- Bottom bar becomes Home, Watch, Polls, Browse, Following (Watch keeps its
  place): check the label fit on the Fold cover screen.

## Phases

| Phase | Delivers | Visible result |
|---|---|---|
| P1. Data (done 12 Oct) | `sources.py`, `results.py`, tables, daily fetch, backfill, `GET /api/polls/list`, `/api/polls/leaders` | `curl` shows every poll since April 2025 with regions |
| P2. Projection (done 12 Oct) | `average.py`, `swing.py`, `backtest.py`, `/api/polls/summary`, `/api/polls/ridings` (no odds yet) | Seat counts per party; back-test numbers in this file |
| P3. Odds + notes | `simulate.py`, `notes.py`, odds in the API, digest line | Majority odds; first weekly note |
| P4. App (tab, riding pages, charts done 12 Oct; MP status in Following to do) | Polls tab, riding page, charts, MP safe/at-risk in Watch follows | The tab on the phone, both screens |
| P5. Release | Fold checks, codebook page, tag (with or without watch Phase 3, decided then) | New ParTake version |

P4 can start once api.md is fixed, alongside P2-P3, against fixtures.

## Back-test result (P2, 12 Oct 2026)

The 2021-transposed baseline was not found, so the back-test projects 2021
from the 2019 result (same 338-riding map) with 338Canada's campaign polls
of 15 Aug-19 Sep 2021 (`python3 -m watch.opinion.backtest`, pinned in
`watch/tests/test_opinion_backtest.py`):

| | LPC | CPC | NDP | BQ | GPC | OTH |
|---|---|---|---|---|---|---|
| Projected | 150 | 115 | 39 | 29 | 1 | 4 |
| Actual | 160 | 119 | 25 | 32 | 2 | 0 |

301 of 338 ridings right (89%). Average error vs the national result: NDP
+1.9, OTH +1.6, GPC +1.3, LPC -1.5, CPC -2.6 points (polls overstated NDP,
as in 2021 coverage). PPC counts as Others throughout, including in
`/api/polls/list`.

## Not in scope

Provincial polls; riding polls (8 published since 2025); demographic
adjustments; pollster ratings; CBC data; any LLM text.
