from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import threading
import unittest


def fake_server(test, status=200, models=None):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_args):
            pass

        def do_POST(self):
            self.server.payload = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
            self.send_response(status)
            self.end_headers()
            self.wfile.write(json.dumps({'embeddings': [[1.0] + [0.0] * 767
                                                       for _ in range(getattr(self.server, 'embedding_count', len(self.server.payload['input'])))]}).encode())

        def do_GET(self):
            self.server.path = self.path
            self.send_response(200)
            self.end_headers()
            self.wfile.write(json.dumps({'models': models or []}).encode())
    server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    def close():
        server.shutdown()
        server.server_close()
        thread.join()
    test.addCleanup(close)
    return server, 'http://127.0.0.1:%d' % server.server_port


def closed_url():
    server = ThreadingHTTPServer(('127.0.0.1', 0), BaseHTTPRequestHandler)
    url = 'http://127.0.0.1:%d' % server.server_port
    server.server_close()
    return url


class EmbedTests(unittest.TestCase):
    def test_01_http_embedding_and_failures(self):
        from watch.embed import embed, EmbedError, MODEL
        server, url = fake_server(self)
        self.assertEqual(len(embed(['one', 'two'], url)), 2)
        self.assertEqual(server.payload, {'model': MODEL, 'input': ['one', 'two']})
        _, bad = fake_server(self, status=500)
        for address in (bad, closed_url()):
            with self.assertRaises(EmbedError):
                embed(['one'], address)
        server.embedding_count = 0
        with self.assertRaisesRegex(EmbedError, 'count mismatch'):
            embed(['one'], url)

    def test_02_pack_and_loaded(self):
        from watch.embed import pack, unpack, dot, loaded, MODEL
        blob = pack([1.0] * 768)
        self.assertEqual(len(blob), 1536)
        self.assertAlmostEqual(dot(unpack(blob), unpack(blob)), 1.0, delta=0.001)
        server, url = fake_server(self, models=[{'name': MODEL + ':latest'}])
        self.assertTrue(loaded(url))
        self.assertEqual(server.path, '/api/ps')
        _, url = fake_server(self, models=[{'model': 'another'}])
        self.assertFalse(loaded(url))
        self.assertFalse(loaded(closed_url()))
