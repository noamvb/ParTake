from contextlib import closing
import http.client
import json
from pathlib import Path
import sqlite3
import tempfile
import threading
import unittest


class StoreTests(unittest.TestCase):
    def test_01_fresh_store(self):
        from watch.api import make_server
        with tempfile.TemporaryDirectory() as data:
            server = make_server(data, "127.0.0.1", 0)
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                conn = http.client.HTTPConnection("127.0.0.1", server.server_port, timeout=3)
                conn.request("GET", "/api/follows")
                response = conn.getresponse()
                self.assertEqual((response.status, json.loads(response.read())),
                                 (200, {"version": 0, "follows": []}))
                conn.close()
                with closing(sqlite3.connect(Path(data) / "watch.db")) as db:
                    tables = {r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
                self.assertTrue({"follows", "meta"}.issubset(tables))
            finally:
                server.shutdown()
                server.server_close()
                thread.join()
