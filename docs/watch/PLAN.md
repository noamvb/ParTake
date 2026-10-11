# Parliament watch: plan

Status: **approved by the owner, 11 Oct 2026** (embedding model still to pick from embeddings-2). Decisions taken in
the grilling session are in [KICKOFF.md](KICKOFF.md); this file turns them into
a build plan. Facts come from the research reports under
[research/](research/) (captions, sources, embeddings, embeddings-2). Anything
marked **verify** has not been measured yet.

Progress lives in the living checklist `partake-watch`
(`~/.ai-orch/bin/checklist show partake-watch`,
http://100.98.120.41:7717/checklists/partake-watch).

## What the research settled

| Question | Answer | Source |
|---|---|---|
| Can the Deck read live captions? | Yes. `ffmpeg -c:v copy` piped into a small H.264 SEI parser reads CEA-608 without decoding video: 1.2% of one core and 111 MB for three streams at once, lowest (SD) rendition, which carries the same captions as HD. Measured on archived streams; live latency **verify** on 19 Oct. | research/captions §1 |
| Does ParlVU say who is speaking? | No. `Speakers` and `AgendaTree` are always `[]`, also in the live poll `GetNewData`. | research/captions §2.1 |
| Can captions tell us who is speaking? | Partly. The Speaker names the next member (by riding or portfolio) in 128 of 143 calls on 9 Oct; committee chairs use surnames. But the same run matched only 19 of 215 Hansard speech changes, so real accuracy is **unknown** - Phase 2 measures it. | research/captions §2.2 |
| Hansard | ourcommons.ca XML (`HAN{n}-E.XML` / `-F.XML`) publishes overnight, 12-20 h after the sitting starts. No public "blues". openparliament.ca imports the same XML a little later. Committee evidence: 2-4 business days. | research/sources Q3 |
| Votes | ourcommons.ca votes XML, per-MP ballot with `PersonId`, same day. 178 divisions so far in 45-1 (re-checked). | research/sources Q4 |
| Bills | LEGISinfo JSON (`parl.ca/legisinfo/en/bill/45-1/c-37/json`), stage timestamps, 191 bills in 45-1. | research/sources Q4 |
| MP identity | ourcommons `PersonId` is the key. openparliament's `parl_mp_id` maps to it and its `parl_affil_id` list maps Hansard `Affiliation DbId` to the person. Member XML (ridings) and ministries XML (portfolios) give the spoken name forms. | research/sources Q5 |
| Backfill start | 45th Parliament opened Mon 26 May 2025 (HAN001 XML). | research/sources Q4 |
| Embedding model | **Pending** the bilingual benchmark (research/embeddings-2). Owner leans to `embeddinggemma-2:270m` (378 MB download). The first run's pick, `all-minilm:33m`, is English-only and is the fallback if memory forces it. Ollama on the Deck runs on CPU (the iGPU is dropped unless `OLLAMA_IGPU_ENABLE=1`). | research/embeddings, embeddings-2 |

## Shape

```
                 ParlVU (events, HLS)      ourcommons.ca / LEGISinfo / openparliament
                        |                                  |
   watch-recorder@<event>  (ffmpeg | sei608)        watch-poller (votes, bills, Hansard,
   one unit per live stream, max 3                   evidence, members, ParlVU calendar)
                        |                                  |
                        +--------> raw/ (append-only JSONL, payload kept only when changed)
                                               |
                                      watch-worker: segment -> speaker guess -> embed (Ollama)
                                               -> match follows -> alerts, digests
                                               |
                                          watch.db (SQLite)
                                               |
                              watch-api (HTTP, 127.0.0.1:8798)
                                               |
                   partake_server.py on the Deck (port 8797): web build + /watch/api proxy
                                               |
                     ParTake Android / web: Watch tab, follow editor, notifications
```

Same rules as election-night: recorders only record, so a matcher bug never
loses data; analysis is pure functions over recorded data, so it can be rerun
(the morning fix-up is a rerun with Hansard in place of captions).

- **Home:** `watch/` in this repo, Python 3.13 standard library only (numpy is
  not installed on the Deck; cosine over a few hundred follow vectors is cheap
  in pure Python, and history search streams vectors from SQLite in chunks).
- **Units (systemd --user):** `partake-watch-api`, `partake-watch-poller`,
  `partake-watch-worker`, templated `partake-watch-recorder@`, and
  `partake-watch-embed` (Ollama, see below). Each has `MemoryMax`. One-off
  jobs (backfill) run with `systemd-run --user --slice=aiorch-agents.slice`.
- **Memory target:** under 1 GB total while the House sits: recorders ~110 MB
  for three, API + poller + worker ~150 MB, embedding model per embeddings-2.
- **Port:** 8798 for the watch API (localhost only); 8797 for ParTake's web
  server on the Deck. 7717, 7718, 8765, 8790, 8796 are taken. deck-hub gets a
  "ParTake" card at `http://100.98.120.41:8797/`.

### Storage

`~/.local/share/partake-watch/`:

- `raw/<source>/<YYYY-MM-DD>.jsonl.gz` - every fetched payload whose hash
  changed, plus every caption line with wall-clock and stream time.
- `watch.db` - SQLite: `members`, `ministries`, `events` (ParlVU),
  `captions`, `paragraphs` (from captions or Hansard, with `source`,
  `event_id`, `offset_s`, `person_id` guess and confidence), `vectors`
  (float16 blobs keyed by paragraph), `bills`, `bill_stages`, `divisions`,
  `ballots`, `follows`, `matches`, `alerts`, `digests`.
- Size estimate **verify** in Phase 1: ~450k paragraphs for the backfill
  (research assumption, not a count) x 768 dims x 2 bytes is ~0.7 GB of
  vectors; text and raw payloads a few GB. The disk has 65 GB free.

### Follows

One list on the Deck, edited from ParTake's Following screen. Kinds:

| Kind | Matches on |
|---|---|
| `topic` | meaning: cosine between the paragraph and the topic's vectors (stored in English AND French so French speech matches an English topic), plus any literal keywords the owner adds |
| `bill` | bill number in text ("C-37", "projet de loi C-37"), LEGISinfo stage changes, divisions on that bill |
| `mp` | `PersonId`: Hansard speeches, ballots, caption speaker guesses |
| `votes` | divisions: `all`, or `party_split` (any party whose MPs voted both ways) |
| `committee`, `house`, `pm-qp` | the existing ParTake follows, moved to the Deck unchanged |

Existing local follows (committee codes, `PM-QP`) upload once on first
connection; after that the Deck is the source of truth and each device
caches the list for offline use, so today's Android alerts keep working
without the Deck.

### Matching

1. Paragraphs: captions are cut at `>>` speaker-change markers and at ~120
   words; Hansard uses its own `<ParaText>` with the speaker attached.
2. Each new paragraph is embedded once (Ollama `/api/embed`, batches of 32)
   and compared with every topic vector; a match above the follow's
   threshold is stored with its score. Thresholds start at a value tuned on
   the embeddings-2 corpus and can be nudged per follow from the app.
3. A new follow is run against history, newest first, so the Watch tab
   fills in within minutes for the recent past and finishes the backfill in
   the background.
4. Morning fix-up: when the sitting's Hansard XML appears (poll from 02:00,
   every 30 min), the caption paragraphs for that sitting are superseded by
   Hansard paragraphs, re-matched, and each match gets links: Hansard
   (ourcommons DocumentViewer), the video at the right time (ParTake deep link
   via the existing caption alignment), the vote, LEGISinfo.

### Live alerts (only two)

1. **A followed bill comes to a vote.** Earliest signal: captions on the
   floor say the division is being called on that bill ("call in the
   members", "the question is on the motion", deferred to a time) while the
   bill is the business in progress; then the ourcommons votes XML confirms
   with the result. Wording patterns **verify** against archived sittings in
   Phase 2.
2. **A followed MP is speaking.** From the caption speaker guess (riding /
   portfolio / committee surname via the members and ministries index). Only
   sent above a confidence threshold, at most once per speech.

Nothing else interrupts. Everything else lands in the digests.

### Digests

- **Evening** (19:30, configurable; only on days with new material): per
  follow, what was said (captions), votes and party splits, bill moves.
- **Morning fix-up** (once Hansard for the previous sitting is in, usually
  before 08:00): the same digest with clean Hansard text and links, marked as
  replacing the evening one. Committee evidence updates later digests as it
  publishes (2-4 days).

Templated text, no LLM (the chat model stays off).

### Ollama on the Deck (owner, 11 Oct 2026: approved)

A separate `partake-watch-embed.service` running its own
Ollama on 127.0.0.1:11436 with only the embedding model,
`OLLAMA_NUM_PARALLEL=1`, `OLLAMA_MAX_LOADED_MODELS=1`, a `MemoryMax`, and a
timer that starts it at 08:30 on sitting days (ParlVU calendar) and stops it
after the evening digest; the morning fix-up and the backfill start it on
demand. The existing `ollama.service` (qwen3 for election-night) is left
alone, so the two never fight over memory or models.

### Pushing alerts to the phone (owner, 11 Oct 2026: Firebase)

Today's alerts use 15-minute background sync plus exact alarms, which is fine
for scheduled meetings but too slow for "MP is speaking" (a speech is often
over in 5-10 minutes). Options, recommended first:

1. **Firebase Cloud Messaging** - instant, battery-friendly, survives Doze, no
   extra app; needs a Firebase project and its key on the Deck.
2. **ntfy over Tailscale** - the Deck runs ntfy, the phone runs the ntfy app
   as a UnifiedPush distributor; no Google account, but needs Tailscale on.
3. **Polling with exact alarms** - no new pieces, but alarms under Doze can be
   ~9 minutes apart, so many speaking alerts arrive late.

### Web build on the Deck (owner, 11 Oct 2026: move it)

ParTake's web build is served today by the Pixelbook (`partake.service`,
port 8790), not the Deck. Decision: also serve it from the Deck on
8797 with `/watch/api` proxied on the same origin, keep the Pixelbook until
the Deck copy is proven, then retire it.

## Phases

Each phase ends with something the owner can see. Work is delegated per
`~/.claude/CLAUDE.md`; the API contract ([api.md](api.md)) lets the service
and the app be built in parallel.

| Phase | Delivers | Visible result | Needs a sitting? |
|---|---|---|---|
| 0. Foundations | `watch/` skeleton, SQLite schema, members/ministries index, follows API, units, Deck web serving + proxy, deck-hub card; app: Deck address setting, follow sync, Following screen gains topics/bills/MPs/votes | Edit follows on the phone, see them on the web | No |
| 1. Records + backfill | pollers (votes, bills, Hansard, evidence); embedding + matching; backfill job since 26 May 2025; Watch tab feed (Android + web) | Watch tab shows past matches for each follow, with links | No |
| 2. Live captions | recorders for House + followed committees; paragraphs; live matching; evening + morning digests; speaker guess + measured accuracy on archived sittings | Evening digest from that day's sitting | Yes for final check (House back 19 Oct) |
| 3. Live alerts | push channel; the two alerts; quiet-hours safety (no sound at night) | Phone alert while a followed MP speaks | Yes |
| 4. Release | cover + inner screen checks on the Fold, docs, codebook page, tagged APK via the release workflow | New ParTake version on the phone | No |

Rough effort: Phase 0 and 1 a few days of delegate work each; Phase 2 about
a week including tuning on real sittings; Phase 3 two to three days plus a
sitting week of testing. The House usually rises mid-December, so Phases 2-3
should be live by mid-November to get four sitting weeks of testing.

## Decisions (owner, 11 Oct 2026)

1. Plan approved.
2. Ollama: a separate embed-only service on a sitting-day timer; the
   existing `ollama.service` stays as it is.
3. Push: Firebase Cloud Messaging. Setting up the Firebase project and
   placing its key on the Deck is a credential step the orchestrator does
   with the owner, never a delegate.
4. Web: serve from the Deck on 8797; retire the Pixelbook copy once proven.
5. Embedding model: picked from the embeddings-2 benchmark; owner leans to
   `embeddinggemma-2:270m`.

## Not in scope

The life dashboard; Senate (SenVU) and Senate debates; any chat LLM;
public access (Tailscale and home network only).
