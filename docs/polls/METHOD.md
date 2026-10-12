# How the Polls projection works

The text the app shows on its "How this works" page (`lib/polls/polls_method.dart`
must match it). Plain language for readers; the technical version is
[PLAN.md](PLAN.md) "Model".

## What it shows

Roughly how many seats each party would win if a federal election were held
today, based on the latest opinion polls. It is a snapshot, not a forecast:
campaigns move votes, and polls can be wrong.

## 1. Polls

Every federal voting-intention poll listed by 338Canada, for Canada as a
whole and for six regions: Atlantic, Quebec, Ontario, the Prairies
(Manitoba and Saskatchewan), Alberta and British Columbia. Read once a day
at 6:30 a.m. Ottawa time, back to the 28 April 2025 election.

## 2. The polling average

For each region:

- Each polling firm counts once, with its latest poll.
- Polls older than 60 days are dropped.
- Bigger polls count more, but not in proportion: a poll four times the size
  counts twice as much.
- Newer polls count more: a poll's weight halves every 14 days.
- Daily tracking polls, which re-report overlapping days, count only for the
  part of the sample that is new.
- Each poll is scaled so its parties add up to 100%.

## 3. From the polls to each riding

Each riding starts from its 2025 election result. If a party has gained a
fifth of its support in the region since the election, its share in each of
that region's ridings grows by a fifth too (proportional swing), and the
riding's shares are scaled back to 100%. A party's share can at most triple.
The three territories follow the national change. The People's Party and
independents count as Others.

## 4. Seats

The party with the highest projected share wins the riding. A majority is
172 of the 343 seats.

## 5. Ranges and odds

The projection is run 10,000 times, each time with random polling error
added: one nationwide error (typically about 2 points), one per region
(about 3 points) and one per riding (about 5 points). The seat number shown
is the middle run; the range covers the middle 80% of runs. Majority odds
are the share of runs in which a party reaches 172 seats. The same day
always gives the same numbers.

The trend chart uses the projection without random error, one point per day.

## 6. Riding status for an MP

From the point of view of the party that holds the seat:

- **Safe**: it keeps the seat in at least 90% of runs.
- **Likely**: at least 70%.
- **At risk**: less than 70%.
- **Projected loss**: another party is projected to win.

## 7. The weekly note

Written automatically from the numbers by fixed rules, after each week ends
(Monday to Sunday). No AI writes it.

## 8. How well it works

Tested on the 2021 election: starting from the 2019 results and using only
the polls from the 2021 campaign, the method picked the right winner in 301
of 338 ridings (89%). It gave the Liberals 150 seats (actual 160) and the
Conservatives 115 (actual 119).

The actual Liberal, Conservative and Bloc seat counts fell inside the
simulated 80% ranges. The NDP won 25 seats, below its range of 33 to 50,
because the 2021 polls overstated NDP support.

## 9. What it leaves out

Riding polls, candidates, incumbency, by-election swings, local campaigns
and demographics. Parties strong in only a few ridings may be under- or
over-counted.

## 10. Sources

- Polls: 338Canada (338canada.com), read for personal use.
- 2025 results: Elections Canada.
- Leader and approval polls: Wikipedia, CC BY-SA 4.0.
- 338Canada's own seat projection is shown for comparison. It uses a
  different, more detailed model.

ParTake is not affiliated with 338Canada, Elections Canada or any polling firm.
