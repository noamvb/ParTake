"""Authenticated follow writes and public Parliament watch lookups."""

import argparse
from datetime import datetime, timezone
import hmac
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import secrets
import sys
import unicodedata
from urllib.parse import parse_qs, urlsplit

from watch.store import (DEFAULT_DATA, StaleVersion, connect, follow_id, import_follows,
                         iso, list_follows, replace_follows)


MAX_BODY = 1024 * 1024


def normalized(value):
    return "".join(c for c in unicodedata.normalize("NFKD", value.casefold()) if not unicodedata.combining(c))


def number_key(value):
    return "".join(c for c in value.casefold() if c.isalnum())


def members(db, query):
    q = normalized(query)
    roles = {}
    for row in db.execute("SELECT * FROM ministries ORDER BY precedence"):
        roles.setdefault(row["person_id"], []).append(row["title"])
    results = []
    for row in db.execute("SELECT * FROM members"):
        name, riding = normalized(row["name"]), normalized(row["riding"])
        if q not in name and q not in riding:
            continue
        last, first = normalized(row["last_name"]), normalized(row["first_name"])
        rank = 0 if last.startswith(q) else 1 if name.startswith(q) else 2
        item = {k: row[k] for k in ("person_id", "name", "party", "riding", "province")}
        item["role"] = "; ".join(roles[row["person_id"]]) if row["person_id"] in roles else None
        results.append(((rank, last, first), item))
    return [item for _key, item in sorted(results, key=lambda r: r[0])[:20]]


def bills(db, query):
    q, number = normalized(query), number_key(query)
    results = []
    for row in db.execute("SELECT * FROM bills"):
        exact = bool(number) and number_key(row["number"]) == number
        if exact or q in normalized(row["title"]):
            results.append(((0 if exact else 1, row["number"]), dict(row)))
    return [item for _key, item in sorted(results, key=lambda r: r[0])[:20]]


def make_server(data_dir, host, port, clock=None, new_id=None):
    data_dir = Path(data_dir).expanduser()
    with connect(data_dir):
        pass
    token_path = data_dir / "token"
    try:
        fd = os.open(token_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        pass
    else:
        with os.fdopen(fd, "w") as token_file:
            token_file.write(secrets.token_urlsafe(24))
    token = token_path.read_text().strip()
    clock = clock or (lambda: datetime.now(timezone.utc))
    new_id = new_id or follow_id

    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, _format, *_args):
            pass

        def _send(self, status, value):
            body = json.dumps(value, ensure_ascii=False).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            if self.command != "HEAD":
                self.wfile.write(body)
            sys.stderr.write("%s %s %d\n" % (self.command, urlsplit(self.path).path, status))

        def _error(self, status, message):
            self._send(status, {"error": message})

        def _body(self):
            try:
                size = int(self.headers.get("Content-Length", "0"))
            except ValueError:
                raise ValueError("invalid content length")
            if size < 0:
                raise ValueError("invalid content length")
            if size > MAX_BODY:
                self.close_connection = True
                raise OverflowError("body too large")
            return json.loads(self.rfile.read(size))

        def _handle(self):
            parts = urlsplit(self.path)
            path = parts.path
            writing = self.command in ("PUT", "POST", "DELETE")
            if writing and not hmac.compare_digest(
                    self.headers.get("Authorization", "").encode(), ("Bearer " + token).encode()):
                self.close_connection = True
                self._error(401, "unauthorized")
                return
            try:
                if self.command in ("GET", "HEAD"):
                    with connect(data_dir) as db:
                        if path == "/api/follows":
                            self._send(200, list_follows(db))
                        elif path == "/api/health":
                            sources = {row["key"][7:]: json.loads(row["value"]) for row in db.execute(
                                "SELECT key,value FROM meta WHERE key LIKE 'source:%'")}
                            self._send(200, {"ok": True, "version": "0.1.0", "now": iso(clock()),
                                             "sitting_today": None, "recorders": [], "embed": None,
                                             "backfill": None, "sources": sources})
                        elif path in ("/api/members", "/api/bills"):
                            query = parse_qs(parts.query).get("q", [""])[0].strip()
                            if not query:
                                raise ValueError("q required")
                            lookup = members if path == "/api/members" else bills
                            self._send(200, lookup(db, query))
                        else:
                            self._error(404, "not found")
                elif (self.command, path) in (("PUT", "/api/follows"), ("POST", "/api/follows/import")):
                    body = self._body()
                    writer = replace_follows if self.command == "PUT" else import_follows
                    self._send(200, writer(data_dir, body, clock, new_id))
                else:
                    self._error(404, "not found")
            except OverflowError:
                self._error(413, "body too large")
            except StaleVersion as exc:
                self._send(409, exc.current)
            except (ValueError, UnicodeError, TypeError) as exc:
                self._error(400, str(exc))
            except Exception:
                self._error(500, "internal server error")

        do_GET = do_HEAD = do_PUT = do_POST = do_DELETE = _handle

        def __getattr__(self, name):
            if name.startswith("do_"):
                return lambda: self._error(404, "not found")
            raise AttributeError(name)

    server = ThreadingHTTPServer((host, port), Handler)
    server.daemon_threads = True
    return server


def main(argv=None):
    parser = argparse.ArgumentParser(description="Serve Parliament watch")
    parser.add_argument("--data", default=DEFAULT_DATA)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8798)
    args = parser.parse_args(argv)
    server = make_server(args.data, args.host, args.port)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
