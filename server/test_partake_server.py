import http.client
import json
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from server.partake_server import allowed_proxy_path, make_server


LISTING = "/Harmony/en/api/Data/GetListViewData?categoryId=-1&fromDate=20260923&endDate=20260923&searchTime=&searchForward=true&order=asc"
EVENT = "/Harmony/en/PowerBrowser/PowerBrowserV2/-1/-1/45806"


class FakeUpstreamHandler(BaseHTTPRequestHandler):
    records = []

    def do_GET(self):
        type(self).records.append((self.path, "GET", dict(self.headers)))
        if self.path.startswith("/Harmony/en/api/Data/GetListViewData"):
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            body = b'{"Weeks": []}'
        elif self.path == EVENT:
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            body = b"<html>event</html>"
        elif self.path.endswith("/-1/-1/99999999"):
            self.send_response(302)
            self.send_header("Location", "/Harmony/en/View/NoEvent")
            body = b""
        elif self.path.endswith("/-1/-1/500"):
            self.send_response(503)
            body = b"unavailable"
        else:
            self.send_response(404)
            body = b"missing"
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_args):
        pass


class PartakeServerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        FakeUpstreamHandler.records = []
        cls.fake = ThreadingHTTPServer(("127.0.0.1", 0), FakeUpstreamHandler)
        cls.fake_thread = threading.Thread(target=cls.fake.serve_forever, daemon=True)
        cls.fake_thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.fake.shutdown()
        cls.fake.server_close()
        cls.fake_thread.join()

    def setUp(self):
        FakeUpstreamHandler.records.clear()
        self.temp = tempfile.TemporaryDirectory()
        root = Path(self.temp.name) / "web"
        root.mkdir()
        (root / "index.html").write_text("<html>index</html>", encoding="utf-8")
        (root / "main.dart.js").write_text("javascript", encoding="utf-8")
        (root / "app.wasm").write_bytes(b"wasm")
        (root / "canvaskit").mkdir()
        (root / "canvaskit/canvaskit.wasm").write_bytes(b"ck")
        (root / "assets").mkdir()
        (root / "assets/x.png").write_bytes(b"png")
        self.root = root
        self.clock_value = [100.0]
        upstream = "http://127.0.0.1:%d" % self.fake.server_port
        self.server = make_server(str(root), "127.0.0.1", 0, upstream, clock=lambda: self.clock_value[0])
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()
        self.temp.cleanup()

    def request(self, path, method="GET", server=None):
        server = server or self.server
        conn = http.client.HTTPConnection("127.0.0.1", server.server_port, timeout=3)
        conn.request(method, path)
        response = conn.getresponse()
        body = response.read()
        result = response.status, dict(response.getheaders()), body
        conn.close()
        return result

    def test_healthz(self):
        status, headers, body = self.request("/healthz")
        self.assertEqual((status, body), (200, b"ok"))
        self.assertEqual(headers["Content-Type"], "text/plain")

    def test_listing_is_proxied_with_headers_and_content(self):
        status, headers, body = self.request("/parlvu" + LISTING)
        self.assertEqual(status, 200)
        self.assertEqual(body, b'{"Weeks": []}')
        self.assertEqual(headers["Content-Type"], "application/json; charset=utf-8")
        self.assertEqual(headers["Cache-Control"], "no-store")
        self.assertEqual(len(FakeUpstreamHandler.records), 1)
        path, method, upstream_headers = FakeUpstreamHandler.records[0]
        self.assertEqual((path, method), (LISTING, "GET"))
        self.assertEqual(upstream_headers["User-Agent"], "ParTake/0.1 (+https://github.com/noamvb/ParTake; personal, non-commercial)")

    def test_event_page_is_proxied(self):
        status, _headers, body = self.request("/parlvu" + EVENT)
        self.assertEqual((status, body), (200, b"<html>event</html>"))

    def test_allowed_proxy_paths(self):
        cases = [
            (LISTING, True),
            (EVENT, True),
            ("/Harmony/en/api/Data/GetCategoryList", False),
            (EVENT + "?x=1", False),
            ("/Harmony/en/PowerBrowser/PowerBrowserV2/-1/-1/abc", False),
            ("/Harmony/en/api/Data/GetListViewData?fromDate=2026092", False),
            ("/Harmony/en/api/Data/GetListViewData?evil=1", False),
            ("/Harmony/en/api/Data/GetListViewData/../../x", False),
            ("//evil.example/x", False),
        ]
        for path, expected in cases:
            with self.subTest(path=path):
                self.assertEqual(allowed_proxy_path(path), expected)

    def test_refused_proxy_path_is_not_forwarded(self):
        status, _headers, body = self.request("/parlvu/Harmony/en/api/Data/GetCategoryList")
        self.assertEqual((status, json.loads(body)), (404, {"error": "not allowed"}))
        self.assertEqual(len(FakeUpstreamHandler.records), 0)

    def test_post_is_rejected_without_upstream_request(self):
        status, _headers, _body = self.request("/parlvu" + EVENT, "POST")
        self.assertEqual(status, 405)
        self.assertEqual(FakeUpstreamHandler.records, [])

    def test_redirect_means_no_such_event_and_is_not_followed(self):
        status, _headers, body = self.request("/parlvu/Harmony/en/PowerBrowser/PowerBrowserV2/-1/-1/99999999")
        self.assertEqual((status, json.loads(body)), (404, {"error": "no such event"}))
        self.assertEqual(len(FakeUpstreamHandler.records), 1)

    def test_upstream_errors_become_502(self):
        status, _headers, body = self.request("/parlvu/Harmony/en/PowerBrowser/PowerBrowserV2/-1/-1/500")
        self.assertEqual((status, json.loads(body)), (502, {"error": "upstream 503"}))
        closed = ThreadingHTTPServer(("127.0.0.1", 0), FakeUpstreamHandler)
        port = closed.server_port
        closed.server_close()
        unreachable = make_server(str(self.root), "127.0.0.1", 0, "http://127.0.0.1:%d" % port)
        thread = threading.Thread(target=unreachable.serve_forever, daemon=True)
        thread.start()
        try:
            status, _headers, body = self.request("/parlvu" + EVENT, server=unreachable)
            self.assertEqual((status, json.loads(body)), (502, {"error": "upstream unreachable"}))
        finally:
            unreachable.shutdown()
            unreachable.server_close()
            thread.join()

    def test_proxy_cache_expires_after_thirty_seconds(self):
        self.request("/parlvu" + LISTING)
        self.request("/parlvu" + LISTING)
        self.assertEqual(len(FakeUpstreamHandler.records), 1)
        self.clock_value[0] += 31
        self.request("/parlvu" + LISTING)
        self.assertEqual(len(FakeUpstreamHandler.records), 2)

    def test_static_files_and_mime_types(self):
        status, headers, body = self.request("/")
        self.assertEqual((status, body), (200, b"<html>index</html>"))
        self.assertEqual(headers["Cache-Control"], "no-cache")
        status, headers, _body = self.request("/main.dart.js")
        self.assertEqual((status, headers["Content-Type"]), (200, "application/javascript"))
        self.assertEqual(headers["Cache-Control"], "no-cache")
        status, headers, _body = self.request("/canvaskit/canvaskit.wasm")
        self.assertEqual((status, headers["Cache-Control"]), (200, "public, max-age=86400"))
        status, headers, body = self.request("/app.wasm")
        self.assertEqual((status, headers["Content-Type"], body), (200, "application/wasm", b"wasm"))

    def test_spa_fallback_and_missing_asset(self):
        status, _headers, body = self.request("/player/45806")
        self.assertEqual((status, body), (200, b"<html>index</html>"))
        self.assertEqual(self.request("/missing.js")[0], 404)

    def test_traversal_paths_do_not_expose_outside_file(self):
        sentinel = Path(self.temp.name) / "secret.txt"
        sentinel.write_text("outside-secret-marker", encoding="utf-8")
        (self.root / "outside-link").symlink_to(sentinel)
        for path in ("/../server/partake_server.py", "/%2e%2e/%2e%2e/etc/passwd", "/assets/../../x", "/outside-link"):
            status, _headers, body = self.request(path)
            self.assertEqual(status, 404, path)
            self.assertNotIn(b"outside-secret-marker", body)

    def test_responses_include_nosniff(self):
        for path in ("/healthz", "/", "/missing.js", "/parlvu" + EVENT):
            _status, headers, _body = self.request(path)
            self.assertEqual(headers["X-Content-Type-Options"], "nosniff", path)


if __name__ == "__main__":
    unittest.main()
