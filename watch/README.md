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
```

The API binds to localhost on port 8798. The timer refreshes lookups at 06:00
local time and catches up after downtime. Data lives in
`~/.local/share/partake-watch/`; the web server proxies the API on port 8797.
Phase 0 includes follows and lookup endpoints only.
