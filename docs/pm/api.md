# PM tracker HTTP API - contract between the Deck service and ParTake

Draft, 14 Oct 2026, part of [PLAN.md](PLAN.md). Served by the watch API
process; same conventions as [../watch/api.md](../watch/api.md) (JSON, ISO
8601 UTC ending in `Z`, Ottawa dates, `{"error": ...}` errors,
`/watch/api/...` through the Deck proxy). All endpoints are reads; no token.
Values in the examples are illustrative.

Item types: `itinerary`, `readout`, `release`, `statement`, `speech`,
`backgrounder` (from the URL path segment `media-advisories`, `readouts`,
`news-releases`, `statements`, `speeches`, `backgrounders`; any other segment
is stored as `other`). Item ids are the pm.gc.ca path after `/en/news/`
(`"readouts/2026/10/14/prime-minister-carney-speaks-president-guyana"`).

A **place** object:

```json
{"id": "calgary-alberta", "name": "Calgary, Alberta", "country": "Canada",
 "lat": 51.0447, "lon": -114.0719, "zone": "America/Edmonton"}
```

`id` is the heading lower-cased with every run of non-letters/digits replaced
by `-`. `lat`/`lon` are `null` until geocoded or when Nominatim found
nothing; `zone` is `null` when unknown.

An **event** object (one timed line of an itinerary):

```json
{"date": "2026-10-15", "local_time": "09:15", "starts_at": "2026-10-15T15:15:00Z",
 "place": {...place...}, "text": "The Prime Minister will meet with community members at a local business.",
 "venue": "West Block, Parliament Hill", "media": "open", "item_id": "media-advisories/2026/10/14/thursday-october-15-2026"}
```

`date` is the itinerary's date; `local_time` is 24-hour `HH:MM` in the
place's zone; `starts_at` is UTC or `null` when the zone is unknown;
`venue` joins the untimed lines that follow the event line before any media
note (`null` when none); `media` is `open` ("Open to media"), `closed`
("Closed to media"), `pool` (any "Pool"/"Pooled" note) or `null`.

## GET /api/pm/today

Today's and tomorrow's itineraries (Ottawa dates) and the "now/next" state.

```json
{"days": [
   {"date": "2026-10-14", "item_id": "media-advisories/2026/10/13/wednesday-october-14-2026",
    "url": "https://www.pm.gc.ca/en/news/media-advisories/2026/10/13/wednesday-october-14-2026",
    "notes": ["Private meetings"], "events": [...event...]},
   {"date": "2026-10-15", "item_id": "...", "url": "...", "notes": [], "events": [...]}],
 "now": {"place": {...place...}, "event": {...event...}},
 "next": {...event...},
 "fetched_at": "2026-10-14T21:30:00Z"}
```

A day with no published itinerary is absent from `days` (0, 1 or 2 entries).
`now.event` is the latest event of today whose `starts_at` has passed (null
if none); `now.place` is that event's place, else the last place of the most
recent itinerary on or before today (null if none). `next` is the first
event with `starts_at` in the future, or null. Times are computed at request
time on the server; the app may recompute them from `starts_at`.

## GET /api/pm/feed

Newest first by `published_at`, paged (`limit` default 50, max 200;
`before`, `next`). Optional `type` filter (comma-separated item types).
Itinerary items are included unless `type` excludes them.

```json
{"items": [{"id": "readouts/2026/10/14/prime-minister-carney-speaks-president-guyana",
   "type": "readout", "title": "Prime Minister Carney speaks with President of Guyana Dr. Mohamed Irfaan Ali",
   "published_at": "2026-10-14T23:18:52Z",
   "url": "https://www.pm.gc.ca/en/news/readouts/2026/10/14/prime-minister-carney-speaks-president-guyana",
   "summary": "Today, the Prime Minister, Mark Carney, spoke with the President of Guyana..."}],
 "next": "opaque-cursor-or-null",
 "source": {"name": "Prime Minister's Office", "url": "https://www.pm.gc.ca/en/news"}}
```

`summary` is the body as plain text, first 280 characters, cut at a word
boundary with `…` when cut. For backfilled items without a feed timestamp,
`published_at` is the path date at 12:00 Ottawa time.

## GET /api/pm/items/{id}

One item with its body. `{id}` is the item id with `/` kept as-is in the path.

```json
{"id": "...", "type": "readout", "title": "...", "published_at": "...", "url": "...",
 "body": "<p>Today, the Prime Minister...</p>",
 "text": "Today, the Prime Minister...",
 "events": []}
```

`body` is the sanitised HTML (tags kept: `p h2 h3 ul ol li strong em a br`;
`a` keeps only `href`); `text` is the plain text. `events` is filled for
itinerary items. Unknown id: 404.

## GET /api/pm/places

Every place the PM has an itinerary event in, for the map.

Query: `since` (date, default `2025-03-14`), `until` (date, default today).

```json
{"places": [{...place..., "visits": 14, "days": 9,
   "first": "2025-03-21", "last": "2026-10-15"}],
 "since": "2025-03-14", "until": "2026-10-14"}
```

`visits` counts events, `days` counts distinct itinerary dates. Places with
`lat` null are listed (the app skips them on the map).

## GET /api/pm/path

The ordered travel path for a date range, for the week view.

Query: `since`, `until` (dates, required, at most 31 days apart; else 400).

```json
{"stops": [{"date": "2026-10-13", "place": {...place...}, "first_time": "09:00", "events": 3}],
 "since": "2026-10-12", "until": "2026-10-18"}
```

One stop per consecutive run of events in the same place, ordered by date
then local time.

## Snapshot (Windows build)

`watch/opinion/export.py` also writes these files under `pm/` in the public
snapshot (same branch as Polls, read as `<base>/pm/<name>.json`):

| File | Content |
|---|---|
| `pm/today.json` | `/api/pm/today` |
| `pm/feed.json` | `/api/pm/feed?limit=200`, `next` set to null |
| `pm/places.json` | `/api/pm/places` (default range) |
| `pm/path.json` | `/api/pm/path` for the last 28 days ending today |

On the snapshot the app shows the feed without opening item bodies (tap opens
the pm.gc.ca page) and the week path only for the last four weeks.
