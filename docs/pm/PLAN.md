# PM tracker: plan

Status: **approved by the owner, 14 Oct 2026** (grilling session). The
app/service contract is [api.md](api.md).

## What it is

A **PM** tab in ParTake that shows where the Prime Minister is and what his
office has published: today's and tomorrow's itinerary, a feed of readouts,
news releases and statements, and a map of his travels. The data side runs
inside the Parliament watch service on the Deck (`watch/pm/`), like Polls.

## Decisions (owner, 14 Oct 2026)

| Question | Decision |
|---|---|
| Content | Itinerary (today + tomorrow, now/next marker), feed of readouts, releases, statements, speeches, and a map |
| Where | New PM tab in the bottom bar, after Polls |
| History | Stored on the Deck; backfilled to 14 March 2025 (Carney sworn in) |
| Map | OpenStreetMap street tiles. Default: one dot per city, sized by visits, time filter (month / year / term). Switch: travel path for a chosen week |
| Alerts | None new; the existing PM-at-Question-Period alert stays as it is |
| Windows | Yes, from the public snapshot (same branch as Polls) |
| Livestreams | Not now |
| Language | English only |
| Release | Next, as v0.8.0, before the mid-November Watch testing |

## Sources (checked 14 Oct 2026)

| Data | Source | Notes |
|---|---|---|
| New items | `https://www.pm.gc.ca/en/news.rss` | Latest **10** items only, no paging. Item `link` path gives the type: `/en/news/{media-advisories,readouts,news-releases,statements,speeches,backgrounders}/YYYY/MM/DD/slug`. `description` is the full HTML body. Itinerary items are titled like `Thursday, October 15, 2026`, posted about 17:00 the day before. |
| Itinerary backfill | `https://www.pm.gc.ca/en/news/media-advisories/YYYY/MM/DD/<weekday>-<month>-<day>-<year>` | The slug is predictable from the itinerary date. The path date may be wrong: the site 301-redirects to the right one (checked: `2025/06/10/wednesday-june-11-2025` -> `2025/06/11/...`). 404 = no itinerary that day. Weekend itineraries can be combined or missing; a miss is fine. |
| Feed backfill | Internet Archive CDX: `https://web.archive.org/cdx/search/cdx?url=pm.gc.ca/en/news/<type>/<year>/&matchType=prefix&fl=original&collapse=urlkey` | The site's own listing pages load by script and give nothing to a plain fetch. CDX lists the URLs (14 Oct: ~1,700 releases, ~1,100 statements, ~1,400 readouts in 2025, fewer in 2026); strip query strings, dedupe, keep dates >= 2025-03-14, then fetch each page **from pm.gc.ca**. Best effort: items the Archive never saw are missing. |
| Page body | The live page's main content | Title from `<h1>`, body from the main content region; the RSS `description` is the same HTML. |
| Places | Nominatim `https://nominatim.openstreetmap.org/search?format=json&limit=1&q=<city>` | Max 1 request/second, real `User-Agent` (watch's `USER_AGENT`), results cached forever in the store. Itineraries only name the city ("Calgary, Alberta", "Brussels, Belgium"). |
| Map tiles | `https://tile.openstreetmap.org/{z}/{x}/{y}.png` | App side; attribution "© OpenStreetMap contributors" shown on the map; app user agent set. |

Politeness: one pm.gc.ca request per second during the backfill, `USER_AGENT`
on every request, raw pages kept under `raw/pm/` so a parser change re-runs
without refetching.

## Itinerary parsing

An itinerary body is a sequence of `<h2>` place headings ("Calgary,&nbsp;Alberta")
each followed by paragraphs starting with a bold time (`<strong>9:15&nbsp;a.m.</strong>`)
and the event text, then optional "Notes for media" lists. Rules:

- Normalise `&nbsp;` to spaces. A paragraph whose text starts with a time
  (`h:mm a.m./p.m.`, also `noon`) starts an event; text before the first
  heading or with no time is a note for the day (e.g. "Private meetings").
- Event fields: local time, text (first sentence block, without the media
  notes), `open_to_media` (notes say "Open to media"), `closed` ("Closed to
  media"), place = the latest heading.
- "Note: All times local". Time zone per place: Canadian province or
  territory -> its zone (Ontario/Quebec `America/Toronto`, with the
  documented exceptions left out); foreign places -> a country table in
  `watch/pm/zones.py`; unknown -> `null`, and the event keeps only its local
  time. UTC is computed with `zoneinfo` when the zone is known.
- Keep the parser's input/output pinned by fixtures from at least five real
  itineraries: a House sitting day in Ottawa, a multi-city domestic day, a
  foreign trip, a "no public events" day, and one from spring 2025.

## Shape

```
watch/pm/                   Python stdlib, same rules as watch/
  sources.py                RSS poll, itinerary backfill, CDX feed backfill, page fetch
  itinerary.py              itinerary HTML -> day notes + events
  places.py                 Nominatim lookup + cache
  zones.py                  province / country -> IANA zone
watch.db tables             pm_items (every published item), pm_events (one row per itinerary event),
                            pm_places (geocode cache)
watch/api.py                /api/pm/* (api.md)
watch/opinion/export.py     also writes pm/*.json into the public snapshot
lib/pm/                     app: client + models
lib/ui/pm_screen.dart       the PM tab: Today, Feed, Map
```

- Poll the RSS every 30 minutes inside the existing `partake-watch-poller`
  (`--sources pm`), plus the daily snapshot export.
- Backfill: `python3 -m watch.pm.sources --backfill`, resumable (skips URLs
  already stored), run once by hand on the Deck.
- Bottom bar becomes Home, Watch, Polls, PM, Browse, Following on Android and
  web; Windows shows Home, Polls, PM, Browse. Check the label fit on the Fold
  cover screen (six tabs).

## Phases

| Phase | Delivers | Visible result |
|---|---|---|
| D1. Data | `watch/pm/*`, tables, RSS poll, backfill, `/api/pm/*`, snapshot export | `curl /api/pm/today` shows tomorrow's itinerary with places |
| A1. App | PM tab with Today, Feed and Map (dots + week path), snapshot client for Windows | The tab on the phone, both screens |
| R. Release | Run backfill on the Deck, Fold checks, codebook page, v0.8.0 | New ParTake version |

D1 and A1 run in parallel against api.md and fixtures.

## Not in scope

Alerts, livestream links, French, cabinet ministers' itineraries, LLM text.
