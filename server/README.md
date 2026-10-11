# ParTake home server

The server uses only Python's standard library. For a local run, point it at a
Flutter web build directory containing `index.html`:

```sh
python3 server/partake_server.py --root build/web --host 127.0.0.1 --port 8790
```

To deploy on the Pixelbook, copy this repository's `server/` directory and the
built `web/` directory to `~/partake/`. Install the user unit and enable it:

```sh
mkdir -p ~/.config/systemd/user
cp ~/partake/server/partake.service ~/.config/systemd/user/partake.service
systemctl --user enable --now partake
```

In ChromeOS Settings -> Linux -> Port forwarding, forward port `8790`.
The service binds to all Linux interfaces and serves the static app plus only
the two allowlisted ParlVU request shapes.

## Deck deployment

Copy the web build to `~/partake/web/`, the server to `~/partake/server/`,
and the watch package to `~/partake/watch/`. Install
`partake-watch-api.service` as described in [watch/README.md](../watch/README.md).
It serves the watch API on localhost port 8798. The Deck web server serves
the app on port 8797 and forwards `/watch/api/` to that API:

```sh
python3 server/partake_server.py --root build/web --host 127.0.0.1 --port 8797 --watch-upstream http://127.0.0.1:8798
mkdir -p ~/.config/systemd/user
cp ~/partake/server/partake-deck.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now partake-deck.service
```

The Deck unit binds to all interfaces; Android and the web app share its
follow list. The Pixelbook's `partake.service` remains separate on port 8790.
