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
