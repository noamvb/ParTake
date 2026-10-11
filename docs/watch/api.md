# Parliament watch HTTP API - contract between the Deck service and ParTake

Draft, 11 Oct 2026, part of [PLAN.md](PLAN.md). The service (`watch/`,
127.0.0.1:8798) and the app are built against this file; change it here
first, then in both.

## Conventions

- Clients reach the API at `/watch/api/...` on the ParTake web origin
  (the Deck's `partake_server.py` proxies it to the service's `/api/...`).
  Android uses the configured Deck address, default
  `http://100.98.120.41:8797`.
- JSON, UTF-8, `Cache-Control: no-store`. Timestamps are ISO 8601 UTC ending
  in `Z`. Dates (`YYYY-MM-DD`) are Ottawa calendar dates.
- Errors: HTTP 4xx/5xx with `{"error": "<message>"}`. Unknown id: 404.
  Bad parameter: 400. Stale `version` on write: 409.
- Writes (`PUT`, `POST`, `DELETE`) need `Authorization: Bearer <token>`; the
  token is generated on the Deck at install (`watch/token`) and typed into
  the app once. Reads need no token (the API is only reachable over the home
  network and Tailscale).
- Ids are strings. MP ids are ourcommons `PersonId` (`"123447"`). Bill ids are
  `"45-1/C-37"`. Division ids are `"45-1/178"`. ParlVU event ids are the
  ParlVU numeric id as a string (`"45735"`).
- Lists are newest first unless stated. Paging: `limit` (default 50, max
  200) and `before` (an opaque `cursor` from the previous page); the
  response carries `next` (cursor or `null`).

## GET /api/health

```json
{"ok": true, "version": "0.1.0", "now": "2026-10-19T14:02:00Z",
 "sitting_today": true,
 "recorders": [{"event": "45901", "title": "HoC Sitting No. 150", "since": "2026-10-19T14:00:05Z", "lines": 812}],
 "embed": {"model": "embeddinggemma-2:270m", "loaded": true},
 "backfill": {"done": 182340, "total": 450112},
 "sources": {"votes": {"at": "2026-10-19T14:01:00Z", "ok": true, "error": null}}}
```

`sources` has one entry per poller: `members`, `ministries`, `votes`,
`bills`, `hansard`, `evidence`, `parlvu`.

## Follows

A follow:

```json
{"id": "f_7k2m", "kind": "topic", "label": "Housing affordability",
 "created_at": "2026-10-12T15:00:00Z",
 "topic": {"phrases": {"en": "housing affordability", "fr": "abordabilité du logement"},
           "keywords": ["CMHC"], "threshold": 0.55},
 "bill": null, "mp": null, "votes": null, "committee": null}
```

Exactly one of the kind objects is non-null, matching `kind`:

| kind | object |
|---|---|
| `topic` | `{"phrases": {"en": str, "fr": str}, "keywords": [str], "threshold": float}` - `fr` may be `""`; the service then fills it from the `en` phrase's nearest bilingual match **verify** or leaves English only |
| `bill` | `{"id": "45-1/C-37", "number": "C-37", "title": str}` |
| `mp` | `{"person_id": "123447", "name": "Billy Morin", "party": "CPC", "riding": "Edmonton Northwest"}` |
| `votes` | `{"filter": "all" \| "party_split"}` |
| `committee` | `{"code": "ETHI"}` (existing ParTake follow key) |
| `house` | `{}` |
| `pm-qp` | `{}` |

### GET /api/follows

```json
{"version": 12, "follows": [ <follow>, ... ]}
```

Ordered by `created_at` ascending.

### PUT /api/follows

Body `{"version": 12, "follows": [ <follow without id/created_at for new ones>, ... ]}`
replaces the whole list. 409 with the current list if `version` is stale; the
app then shows the server list and re-applies its one change. Returns the new
`{"version": 13, "follows": [...]}`. Removing a follow keeps its past matches
in the database but hides them from the feed.

### POST /api/follows/import

First-connection migration. Body `{"keys": ["ETHI", "PM-QP", "HOUSE"]}` (the
app's existing local follow keys). Adds the ones not present; returns the list
like GET. Idempotent.

## Lookups for the follow editor

- `GET /api/members?q=morin` -> `[{"person_id", "name", "party", "riding", "province", "role"}]`
  (`role` is the ministry title or `null`; max 20, best match first).
- `GET /api/bills?q=c-37` -> `[{"id", "number", "title", "stage", "stage_at"}]` (max 20).
- `POST /api/topics/preview` body `{"en": "...", "fr": "..."}` -> the 10 best
  matching paragraphs from history with scores, so the owner can pick a
  threshold before saving. Write-token not required (read-only).

## GET /api/feed

Query: `follow=<id>` (optional, repeatable), `kind=speech|division|bill_stage`
(optional), `limit`, `before`.

```json
{"items": [{
   "id": "m_91af", "kind": "speech", "at": "2026-10-19T14:31:12Z",
   "follows": [{"id": "f_7k2m", "score": 0.71}],
   "source": "captions", "superseded": false,
   "title": "Government Orders - Bill C-12",
   "text": "…the paragraph that matched…",
   "lang": "en",
   "speaker": {"person_id": "123447", "name": "Billy Morin", "party": "CPC",
               "confidence": 0.8, "from": "caption_call"},
   "video": {"event": "45901", "offset_s": 1872.0},
   "links": {"hansard": null, "legisinfo": null, "division": null},
   "division": null, "bill_stage": null}],
 "next": "c_…"}
```

- `source` is `captions` (same day) or `hansard` / `evidence` (after the
  morning fix-up). When Hansard replaces a caption item, the caption item
  disappears from the feed and the Hansard item carries the same `follows`;
  clients that cached the old id get 404 for it and should drop it.
- `speaker` is `null` when unknown. `from` is `caption_call` (Speaker or
  Chair named the member), `hansard`, or `ballot`.
- `video` is `null` when no ParlVU recording is known; otherwise the app opens
  its player at `offset_s`.
- For `kind: "division"`: `division` is
  `{"id": "45-1/178", "number": 178, "bill": "45-1/C-37" | null,
    "description": str, "result": "agreed" | "negatived",
    "yeas": int, "nays": int, "paired": int,
    "parties": [{"party": "CPC", "yea": int, "nay": int, "split": bool}],
    "mps": [{"person_id": str, "vote": "yea" | "nay" | "paired"}]}`
  where `mps` lists only followed MPs.
- For `kind: "bill_stage"`: `bill_stage` is
  `{"bill": "45-1/C-37", "number": "C-37", "stage": str, "chamber": "house" | "senate", "at": str}`.

## Digests

### GET /api/digests

`[{"id": "d_2026-10-19_evening", "date": "2026-10-19", "kind": "evening" | "morning",
   "created_at": str, "replaces": null | "d_…", "items": int}]` newest first, `limit`.

### GET /api/digests/{id}

```json
{"id": "d_2026-10-20_morning", "date": "2026-10-19", "kind": "morning",
 "replaces": "d_2026-10-19_evening",
 "sections": [{"follow": {"id": "f_7k2m", "label": "Housing affordability"},
               "items": [ <feed item>, ... ]}]}
```

Sections follow the order of the follows list; follows with nothing new are
left out.

## Alerts

### GET /api/alerts?since=<timestamp>

The app's catch-up and history view; push carries the same objects.

```json
[{"id": "a_33c1", "at": "2026-10-19T15:02:40Z",
  "kind": "bill_vote" | "mp_speaking",
  "follow": "f_bill_c37",
  "title": "Vote called on Bill C-37",
  "body": "Third reading. Members are being called in.",
  "video": {"event": "45901", "offset_s": 4410.0, "live": true},
  "division": null}]
```

Oldest first. `bill_vote` may be sent twice for one vote: once when called
(`division: null`) and once with the recorded result (`division` as in the
feed).

### POST /api/push/register

Body `{"channel": "fcm" | "ntfy", "token": str, "device": str}`; only once the
push channel is chosen (see PLAN.md). Returns `{"ok": true}`.

## GET /api/live

What the recorders hear right now (for the Watch tab's live strip):

```json
[{"event": "45901", "title": "HoC Sitting No. 150", "kind": "house" | "committee",
  "speaker": <speaker or null>, "last_line_at": str,
  "business": "Government Orders - Bill C-12" | null}]
```
