#!/usr/bin/env python3
"""Static web server and narrowly scoped ParlVU proxy for ParTake."""

import argparse
from collections import OrderedDict
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import re
import sys
import threading
import time
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qsl, unquote, urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener


USER_AGENT = "ParTake/0.1 (+https://github.com/noamvb/ParTake; personal, non-commercial)"
LISTING_PATH = "/Harmony/en/api/Data/GetListViewData"
UPCOMING_PATH = "/Harmony/en/api/Data/GetUpcomingEvents"
EVENT_RE = re.compile(r"^/Harmony/en/PowerBrowser/PowerBrowserV2/-1/-1/[0-9]+$")
QUERY_KEYS = {"categoryId", "fromDate", "endDate", "searchTime", "searchForward", "order"}
MAX_CACHE_ENTRIES = 64
MAX_CACHE_BODY = 4 * 1024 * 1024
CACHE_SECONDS = 30


def allowed_proxy_path(path_and_query: str) -> bool:
    """Return whether a path and query match one of the three ParlVU routes."""
    parts = urlsplit(path_and_query)
    path = unquote(parts.path)
    if parts.scheme or parts.netloc or not path.startswith("/") or path.startswith("//") or "\\" in path:
        return False
    if any(segment in (".", "..") for segment in path.split("/")):
        return False
    if path == LISTING_PATH:
        try:
            pairs = parse_qsl(parts.query, keep_blank_values=True, strict_parsing=True)
        except ValueError:
            return False
        if any(key not in QUERY_KEYS for key, _value in pairs):
            return False
        values = {}
        for key, value in pairs:
            values.setdefault(key, []).append(value)
        for key in ("fromDate", "endDate"):
            if key in values and any(not re.fullmatch(r"[0-9]{8}", value) for value in values[key]):
                return False
        return True
    if path == UPCOMING_PATH:
        try:
            pairs = parse_qsl(parts.query, keep_blank_values=True, strict_parsing=True)
        except ValueError:
            return False
        return len(pairs) == 1 and pairs[0][0] == "lastModified" and (
            pairs[0][1] == "" or re.fullmatch(r"[0-9]{17}", pairs[0][1]) is not None
        )
    return not parts.query and bool(EVENT_RE.fullmatch(path))


class _NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class _Cache:
    """Small process-local LRU cache; the lock also coalesces simultaneous misses."""

    def __init__(self, clock):
        self.clock = clock
        self.lock = threading.RLock()
        self.entries = OrderedDict()

    def get_or_fetch(self, key, fetch):
        # Keep the lock through the fetch so concurrent requests for one key wait
        # for the first fetch and then observe its newly cached result.
        with self.lock:
            now = self.clock()
            cached = self.entries.get(key)
            if cached is not None:
                expires, value = cached
                if expires > now:
                    self.entries.move_to_end(key)
                    return value
                del self.entries[key]
            value = fetch()
            status, headers, body = value
            if status == 200 and len(body) <= MAX_CACHE_BODY:
                self.entries[key] = (self.clock() + CACHE_SECONDS, value)
                self.entries.move_to_end(key)
                while len(self.entries) > MAX_CACHE_ENTRIES:
                    self.entries.popitem(last=False)
            return value


def _json_body(value):
    return json.dumps({"error": value}, separators=(",", ":")).encode("utf-8")


def make_server(root: str, host: str, port: int, upstream: str, clock=None) -> ThreadingHTTPServer:
    """Create a configured server. ``clock`` is injectable for cache tests."""
    root_path = Path(root).resolve()
    if not root_path.is_dir():
        raise ValueError("root must be a directory")
    upstream = upstream.rstrip("/")
    clock = clock or time.monotonic
    cache = _Cache(clock)
    opener = build_opener(_NoRedirect())

    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def __getattr__(self, name):
            # BaseHTTPRequestHandler otherwise returns 501 for unknown verbs.
            if name.startswith("do_"):
                return self._method_not_allowed
            raise AttributeError(name)

        def log_message(self, _format, *_args):
            pass

        def _send(self, status, body=b"", content_type="application/octet-stream", cache_control=None, head=False):
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("X-Content-Type-Options", "nosniff")
            if cache_control:
                self.send_header("Cache-Control", cache_control)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            if not head:
                self.wfile.write(body)

        def _json_error(self, status, message, head=False):
            self._send(status, _json_body(message), "application/json", "no-store", head)

        def do_GET(self):
            self._handle(head=False)

        def do_HEAD(self):
            self._handle(head=True)

        def do_POST(self):
            self._method_not_allowed()

        def do_PUT(self):
            self._method_not_allowed()

        def do_DELETE(self):
            self._method_not_allowed()

        def do_PATCH(self):
            self._method_not_allowed()

        def do_OPTIONS(self):
            self._method_not_allowed()

        def do_TRACE(self):
            self._method_not_allowed()

        def _method_not_allowed(self):
            started = time.monotonic()
            path = urlsplit(self.path).path
            self._json_error(405, "method not allowed", self.command == "HEAD")
            self._log(path, 405, started)

        def _log(self, path, status, started):
            elapsed = (time.monotonic() - started) * 1000
            sys.stderr.write("%s %s %d %.1fms\n" % (self.command, path, status, elapsed))
            sys.stderr.flush()

        def _handle(self, head):
            started = time.monotonic()
            status = 500
            parts = urlsplit(self.path)
            raw_path = parts.path
            decoded_path = unquote(raw_path)
            try:
                if decoded_path == "/healthz":
                    status = 200
                    self._send(status, b"ok", "text/plain", head=head)
                    return
                if decoded_path.startswith("/parlvu/"):
                    relative = self.path[len("/parlvu"):]
                    if not allowed_proxy_path(relative):
                        status = 404
                        self._json_error(status, "not allowed", head)
                        return
                    if self.command == "GET":
                        status, headers, body = cache.get_or_fetch(relative, lambda: self._fetch(relative, "GET"))
                    else:
                        status, headers, body = self._fetch(relative, "HEAD")
                    if status == 302 and "/Harmony/en/View/NoEvent" in headers.get("Location", ""):
                        status = 404
                        body = _json_body("no such event")
                        self._send(status, body, "application/json", "no-store", head)
                    elif status >= 500:
                        self._json_error(502, "upstream %d" % status, head)
                        status = 502
                    elif status < 200 or status >= 300:
                        self._json_error(502, "upstream unreachable", head)
                        status = 502
                    else:
                        self._send(status, body, headers.get("Content-Type", "application/octet-stream"), "no-store", head)
                    return
                self._serve_static(decoded_path, head)
                status = self._last_static_status
            except Exception:
                status = 500
                if not self.wfile.closed:
                    try:
                        self._json_error(500, "internal server error", head)
                    except (BrokenPipeError, ConnectionResetError):
                        pass
            finally:
                log_path = raw_path if raw_path.startswith("/parlvu/") else decoded_path
                self._log(log_path, status, started)

        def _fetch(self, path_and_query, method):
            request = Request(
                upstream + path_and_query,
                headers={"User-Agent": USER_AGENT, "Accept": "application/json, text/html"},
                method=method,
            )
            try:
                with opener.open(request, timeout=20) as response:
                    return response.status, dict(response.headers.items()), response.read()
            except HTTPError as exc:
                return exc.code, dict(exc.headers.items()), exc.read()
            except (URLError, TimeoutError, OSError):
                return 0, {}, b""

        def _serve_static(self, path, head):
            self._last_static_status = 404
            if path == "/":
                candidate = root_path / "index.html"
            else:
                relative = path.lstrip("/")
                candidate = (root_path / relative).resolve()
                try:
                    candidate.relative_to(root_path)
                except ValueError:
                    self._send(404, b"not found", "text/plain", "no-store", head)
                    return
                if ".." in Path(relative).parts:
                    self._send(404, b"not found", "text/plain", "no-store", head)
                    return
            if not candidate.is_file():
                if Path(path).suffix:
                    self._send(404, b"not found", "text/plain", "no-store", head)
                    return
                candidate = root_path / "index.html"
            if not candidate.is_file():
                self._send(404, b"not found", "text/plain", "no-store", head)
                return
            body = candidate.read_bytes()
            mime = {
                ".html": "text/html; charset=utf-8",
                ".js": "application/javascript",
                ".mjs": "application/javascript",
                ".json": "application/json",
                ".wasm": "application/wasm",
                ".css": "text/css",
                ".png": "image/png",
                ".ico": "image/x-icon",
                ".svg": "image/svg+xml",
                ".otf": "font/otf",
                ".ttf": "font/ttf",
            }.get(candidate.suffix.lower(), "application/octet-stream")
            # Flutter's web file names are not content-hashed, so everything
            # revalidates except the CanvasKit engine, which only changes with
            # a Flutter upgrade.
            in_canvaskit = candidate.relative_to(root_path).parts[:1] == ("canvaskit",)
            cache_control = "public, max-age=86400" if in_canvaskit else "no-cache"
            self._last_static_status = 200
            self._send(200, body, mime, cache_control, head)

    server = ThreadingHTTPServer((host, port), Handler)
    server.daemon_threads = True
    return server


def main(argv=None):
    parser = argparse.ArgumentParser(description="Serve ParTake and its locked-down ParlVU proxy")
    parser.add_argument("--root", required=True)
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8790)
    parser.add_argument("--upstream", default="https://parlvu.parl.gc.ca")
    args = parser.parse_args(argv)
    server = make_server(args.root, args.host, args.port, args.upstream)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
