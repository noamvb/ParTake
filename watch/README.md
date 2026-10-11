# Parliament watch

The API and lookup ingest use only Python 3.13's standard library. Run from
the repository root with a temporary data directory:

```sh
D=$(mktemp -d)
python3 -m watch.ingest --data "$D"
python3 -m watch.api --data "$D" --host 127.0.0.1 --port 8798
```

The ingest fetches members, current ministry titles and bills. It retains the
previous lookup table if a source fails; the API health response records each
source's last attempt. Raw payloads are appended only when their hash changes.
The API stores follows in SQLite, retaining removed rows, and creates a private
token in `$D/token`. Reads require no token; writes use
`Authorization: Bearer <token>`. Stop the API with Ctrl-C, then remove the
temporary directory with `rm -rf "$D"`.

To install on the Deck, copy the repository's `watch/` package to
`~/partake/watch/`. Install the user units from that checkout:

```sh
mkdir -p ~/.config/systemd/user
cp ~/partake/watch/systemd/partake-watch-api.service ~/.config/systemd/user/
cp ~/partake/watch/systemd/partake-watch-ingest.service ~/.config/systemd/user/
cp ~/partake/watch/systemd/partake-watch-ingest.timer ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user start partake-watch-ingest.service
systemctl --user enable --now partake-watch-api.service partake-watch-ingest.timer
cp ~/partake/watch/systemd/partake-watch-embed.service ~/.config/systemd/user/
cp ~/partake/watch/systemd/partake-watch-poll.service ~/.config/systemd/user/
cp ~/partake/watch/systemd/partake-watch-poll.timer ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now partake-watch-embed.service partake-watch-poll.timer
cp ~/partake/watch/systemd/partake-watch-live.service ~/.config/systemd/user/
cp ~/partake/watch/systemd/partake-watch-recorder@.service ~/.config/systemd/user/
cp ~/partake/watch/systemd/partake-watch-digest-*.service ~/.config/systemd/user/
cp ~/partake/watch/systemd/partake-watch-digest-*.timer ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now partake-watch-live.service partake-watch-digest-evening.timer partake-watch-digest-morning.timer
```

The API binds to localhost on port 8798. The timer refreshes lookups at 06:00
local time and catches up after downtime. Data lives in
`~/.local/share/partake-watch/`; the web server proxies the API on port 8797.


The live supervisor starts recorders; do not enable individual recorder instances.
Install the digest units once `watch.digest` is deployed with the checkout.

| Unit | Purpose |
| --- | --- |
| `partake-watch-api.service` | Serve the local watch API. |
| `partake-watch-ingest.service` / `.timer` | Refresh member and bill lookups daily. |
| `partake-watch-embed.service` | Keep the separate Ollama server available. |
| `partake-watch-poll.service` / `.timer` | Poll records and ParlVU, then embed and match every 30 minutes. |
| `partake-watch-live.service` | Refresh upcoming events every 60 seconds, record the House and followed committees (at most three), and match captions every 120 seconds while recording. |
| `partake-watch-recorder@.service` | Record one event; restart failures after 15 seconds, limited to six starts per 15 minutes. The supervisor resets failed units before starting still-live events again. |
| `partake-watch-digest-evening.service` / `.timer` | Build the evening digest at 19:30 Ottawa time. |
| `partake-watch-digest-morning.service` / `.timer` | Refresh the morning digest every 30 minutes from 06:00 through 11:00 Ottawa time; both digest timers catch up after downtime. |

## Records, embeddings and the feed (Phase 1)

`python3 -m watch.poll --data "$D" [--sources hansard,evidence,votes,bills] [--max-docs N]`
fetches new Hansard sittings, committee evidence (meetings listed by
openparliament.ca), divisions with their ballots, and bill stages, pausing
1 s between requests. Each source's last attempt appears under `sources` in
`/api/health`.

`python3 -m watch.worker --data "$D" [--ollama URL] [--max-batches N]` embeds
paragraphs newest first (batches of 32) with `paraphrase-multilingual` and
matches follows; `/api/health` shows `backfill` progress. Without Ollama it
still matches bills, MPs and votes and exits 1.

`partake-watch-embed.service` runs the separate Ollama 0.40.2 in
`~/.local/ollama-watch` on 127.0.0.1:11436, always on; the model unloads after
5 idle minutes (about 60 MB idle, about 1.2 GB loaded).
`partake-watch-poll.timer` starts `partake-watch-poll.service` every 30
minutes: poll, then embed and match. The first run is the backfill since
26 May 2025 and takes hours; later runs skip while one is active.
`GET /api/feed` serves the matches (see `docs/watch/api.md`).

`python3 -m watch.recorder --data "$D" --event ID` records English CEA-608
captions from the event's HLS stream (the event must already have `stream_url`).
It commits rows when they leave the display, stores millisecond UTC times using
recording time for VOD or a persisted live anchor, and resumes after the last
stored media sequence. It leaves archive captions intact, retries failed
fetches three times, and stops at ENDLIST or after ten minutes without a new
segment; an exit code of 1 lets a supervisor restart it, while 2 means the
stream is missing.

The optional `parlvu` source (`python3 -m watch.poll --sources parlvu --data "$D"`)
loads House sittings and committee video events one Ottawa day at a time,
backfilling from 26 May 2025 and refreshing yesterday, today and upcoming events.
Each run loads English archived captions for up to five adjourned events,
retains raw listings and event pages, and records its health under `parlvu`.
Pages without captions are retried up to three times; requests pause 1 s apart.

## Caption paragraphs and speaker accuracy (Phase 2)

`watch.speaker.CallIndex(members_rows, ministries_rows)` resolves the last
call in a presiding speech by riding (exact or a conservative fuzzy match),
ministry title, or a unique surname when `committee=True`. `label(text)`
recognizes presiding and interpreter labels, including bracketed interpreter
labels. Unknown or ambiguous calls return no guess; incomplete titles and
heavily garbled riding names are left unknown.

`watch.segment.segment_event(db, event_id, index)` writes complete caption
speeches as paragraphs of at most 200 words; `segment_all(db, index)` handles
eligible events without an official document. Segmentation starts with archive
captions when available, otherwise live captions, and keeps that source after
paragraphs exist. The `segment:<event>` metadata saves the line and character
cursor, speech and paragraph numbers, speaker state, and speech spans. Repeated
calls resume without duplicate text, and an adjourned archive's final speech
can be extended when another batch arrives. A call applies to one member
speech, with interpreter speeches inheriting the guess.

`watch.align.align(interventions, lines)` matches the first eight normalized
English tokens of each official intervention against caption words within
one minute before to seven minutes after its minute bucket. Matches require
at least five equal tokens, preserve chronological order, and retain the first
best score on a tie. Bisected word times bound each search; unmatched or short
interventions return `None`, with no interpolation.

`watch.accuracy.measure(db, event_id)` compares guesses with stored official
speakers at aligned caption speech times. Run
`python3 -m watch.accuracy --data "$D" --event 45735 --event 45822` to print one
JSON object per event with counts, precision, recall, results by call type,
and up to 20 errors (including missed guesses). Both official and caption
paragraphs must already be stored. Fixture precision/recall are 87.9%/28.4%
for House sitting 149 and 100%/16.7% for INDU meeting 50; abbreviations, missing
calls, and distorted captions limit recall under the conservative rules.

`watch.fixup.fixup(db, now)` supersedes caption paragraphs once their official
Hansard or evidence is stored, aligns official interventions to archive captions
(or live captions when no archive exists), and falls back to in-window official
timestamps. Missing captions defer a fix-up for 48 hours; each document commits
atomically and its `fixup:<document>` metadata makes repeated passes idempotent.
The worker segments captions and runs fix-ups before matching, recording failures
under `source:segment` and `source:fixup` without stopping matching.

`python3 -m watch.digest --data "$D" --kind evening|morning [--date YYYY-MM-DD]`
saves active-follow feed snapshots for an Ottawa calendar date. Evening defaults
to today; morning builds missing digests for the preceding three dates with stored
Hansard. Morning digests reference the evening digest when present; superseded
paragraphs are excluded. Each built digest prints `id items` with distinct item
counts. Tests can override the default Ottawa date using hidden `--today YYYY-MM-DD`;
this does not change the digest's creation timestamp. `/api/digests` lists saved
digests and `/api/digests/<id>` returns the snapshot.
