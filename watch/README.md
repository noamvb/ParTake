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
```

The API binds to localhost on port 8798. The timer refreshes lookups at 06:00
local time and catches up after downtime. Data lives in
`~/.local/share/partake-watch/`; the web server proxies the API on port 8797.


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
