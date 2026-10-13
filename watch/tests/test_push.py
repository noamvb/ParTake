from contextlib import redirect_stdout
from datetime import datetime, timedelta, timezone
import base64
import http.client
import io
import json
from pathlib import Path
import subprocess
import tempfile
import threading
import unittest

from watch import push
from watch.store import add_alert, connect


NOW = datetime(2026, 10, 19, 16, 0, tzinfo=timezone.utc)
OPENSSL = "/usr/bin/openssl"
API_ALERT = {"id": "a_33c1", "at": "2026-10-19T15:02:40Z", "kind": "bill_vote", "follow": "f_bill_c37",
             "title": "Vote called on Bill C-37", "body": "Third reading. Members are being called in.",
             "video": {"event": "45901", "offset_s": 4410.0, "live": True}, "division": None}
API_MESSAGE_ALERT = ('{"at":"2026-10-19T15:02:40Z","body":"Third reading. Members are being called in.",'
                     '"division":null,"follow":"f_bill_c37","id":"a_33c1","kind":"bill_vote",'
                     '"title":"Vote called on Bill C-37","video":{"event":"45901","live":true,"offset_s":4410.0}}')


class FakeSender:
    def __init__(self, result=(True, None, False)):
        self.result = result
        self.calls = []

    def send(self, token, data):
        self.calls.append((token, data))
        return self.result


class PushTestCase(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.data = Path(self.temp.name)

    def register(self, db, device="dev1", at=NOW - timedelta(hours=1), token="tok-1"):
        push.register(db, {"channel": "fcm", "token": token, "device": device}, at)

    def alert(self, db, at, title="Speaking", dedupe=None):
        return add_alert(db, dict(at=push.iso(at) if isinstance(at, datetime) else at, kind="mp_speaking",
                                  follow="f_abc234", title=title, body="Body", video=None, division=None),
                         dedupe or title + str(at))

    def outbox(self, db):
        return [dict(row) for row in db.execute("SELECT alert, device, state, attempts FROM push_outbox")]


class QuietTests(unittest.TestCase):
    def quiet_at(self, *stamps):
        return [push.is_quiet(datetime.fromisoformat(stamp)) for stamp in stamps]

    def test_quiet_boundaries_edt(self):
        # 2026-10-19 is EDT (UTC-4) in Ottawa.
        self.assertEqual(self.quiet_at("2026-10-20T01:59:59Z", "2026-10-20T02:00:00Z",
                                       "2026-10-19T11:59:59Z", "2026-10-19T12:00:00Z"),
                         [False, True, True, False])

    def test_quiet_boundaries_est(self):
        # 2026-12-01 is EST (UTC-5) in Ottawa.
        self.assertEqual(self.quiet_at("2026-12-02T02:59:59Z", "2026-12-02T03:00:00Z",
                                       "2026-12-01T12:59:59Z", "2026-12-01T13:00:00Z"),
                         [False, True, True, False])


class MessageTests(unittest.TestCase):
    def test_message_exact_output(self):
        alert = {"at": "2026-10-19T15:02:40Z", "body": "B", "division": None, "follow": "f_1",
                 "id": "a_1", "kind": "mp_speaking", "title": "T", "video": None}
        self.assertEqual(push.message(alert, True), {
            "type": "alert",
            "alert": '{"at":"2026-10-19T15:02:40Z","body":"B","division":null,"follow":"f_1",'
                     '"id":"a_1","kind":"mp_speaking","title":"T","video":null}',
            "quiet": "1"})
        self.assertEqual(push.message(alert, False)["quiet"], "0")

    def test_literal_data_decodes_to_api_example(self):
        data = {"type": "alert", "quiet": "1", "alert": API_MESSAGE_ALERT}
        self.assertEqual(json.loads(data["alert"]), API_ALERT)
        self.assertEqual(set(data), {"type", "alert", "quiet"})
        self.assertTrue(all(isinstance(value, str) for value in data.values()))

    def test_fcm_body_exact_and_no_notification(self):
        body = push.fcm_body("tok", {"type": "alert", "quiet": "0"})
        self.assertEqual(body, {"message": {"token": "tok", "data": {"type": "alert", "quiet": "0"},
                                            "android": {"priority": "high", "ttl": "600s"}}})

        def has_key(value, key):
            if isinstance(value, dict):
                return key in value or any(has_key(v, key) for v in value.values())
            if isinstance(value, list):
                return any(has_key(v, key) for v in value)
            return False
        self.assertFalse(has_key(body, "notification"))
        self.assertTrue(has_key({"message": {"x": [{"notification": 1}]}}, "notification"))


class SenderTests(PushTestCase):
    @classmethod
    def setUpClass(cls):
        cls.key_dir = tempfile.TemporaryDirectory()
        cls.key_path = Path(cls.key_dir.name) / "key.pem"
        cls.pub_path = Path(cls.key_dir.name) / "pub.pem"
        subprocess.run([OPENSSL, "genpkey", "-algorithm", "RSA", "-pkeyopt", "rsa_keygen_bits:2048",
                        "-out", str(cls.key_path)], check=True, capture_output=True)
        subprocess.run([OPENSSL, "rsa", "-in", str(cls.key_path), "-pubout", "-out", str(cls.pub_path)],
                       check=True, capture_output=True)

    @classmethod
    def tearDownClass(cls):
        cls.key_dir.cleanup()

    def service_account(self, token_uri="https://oauth2.googleapis.com/token"):
        path = self.data / "fcm-service-account.json"
        path.write_text(json.dumps({"project_id": "partake-test", "client_email": "svc@partake-test.iam",
                                    "private_key": self.key_path.read_text(), "token_uri": token_uri}))
        return path

    def fake_transport(self, send_status=200, send_body=b"{}", token_calls=None):
        calls = [] if token_calls is None else token_calls

        def transport(url, body, headers):
            calls.append((url, body, headers))
            if url.startswith("https://fcm.googleapis.com/"):
                return send_status, send_body
            return 200, json.dumps({"access_token": "ya29.test", "expires_in": 3600}).encode()
        return transport, calls

    def test_access_token_jwt_claims_signature_and_cache(self):
        token_calls = []
        transport, _ = self.fake_transport(token_calls=token_calls)
        clock = [NOW]
        sender = push.FcmSender(self.service_account(), transport=transport, clock=lambda: clock[0])
        self.assertEqual(sender.access_token(), "ya29.test")
        url, body, headers = token_calls[0]
        self.assertEqual(url, "https://oauth2.googleapis.com/token")
        self.assertEqual(headers["Content-Type"], "application/x-www-form-urlencoded")
        prefix = "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion="
        self.assertTrue(body.decode().startswith(prefix))
        jwt = body.decode()[len(prefix):]
        header_part, claims_part, sig_part = jwt.split(".")

        def b64decode(part):
            return base64.urlsafe_b64decode(part + "=" * (-len(part) % 4))
        self.assertEqual(json.loads(b64decode(header_part)), {"alg": "RS256", "typ": "JWT"})
        iat = int(NOW.timestamp())
        self.assertEqual(json.loads(b64decode(claims_part)), {
            "iss": "svc@partake-test.iam", "scope": "https://www.googleapis.com/auth/firebase.messaging",
            "aud": "https://oauth2.googleapis.com/token", "iat": iat, "exp": iat + 3600})

        signed = self.data / "signing-input"
        signed.write_bytes(f"{header_part}.{claims_part}".encode())
        sig = self.data / "signature"
        sig.write_bytes(b64decode(sig_part))
        verify = subprocess.run([OPENSSL, "dgst", "-sha256", "-verify", str(self.pub_path),
                                 "-signature", str(sig), str(signed)], capture_output=True, text=True)
        self.assertEqual(verify.returncode, 0, verify.stderr)
        self.assertIn("Verified OK", verify.stdout)

        self.assertEqual(sender.access_token(), "ya29.test")
        self.assertEqual(len(token_calls), 1)
        clock[0] = NOW + timedelta(seconds=3541)
        sender.access_token()
        self.assertEqual(len(token_calls), 2)

    def test_send_ok_and_unregistered(self):
        transport, _ = self.fake_transport(send_status=200)
        sender = push.FcmSender(self.service_account(), transport=transport, clock=lambda: NOW)
        self.assertEqual(sender.send("tok", {"type": "alert", "quiet": "0"}), (True, None, False))

        transport, calls = self.fake_transport(
            send_status=404, send_body=b'{"error":{"status":"NOT_FOUND","details":[{"errorCode":"UNREGISTERED"}]}}')
        sender = push.FcmSender(self.service_account(), transport=transport, clock=lambda: NOW)
        ok, error, gone = sender.send("tok", {"type": "alert", "quiet": "0"})
        self.assertFalse(ok)
        self.assertTrue(gone)
        self.assertIn("UNREGISTERED", error)
        send_url, send_body, send_headers = calls[-1]
        self.assertEqual(send_url, "https://fcm.googleapis.com/v1/projects/partake-test/messages:send")
        self.assertEqual(json.loads(send_body), push.fcm_body("tok", {"type": "alert", "quiet": "0"}))
        self.assertEqual(send_headers["Authorization"], "Bearer ya29.test")

    def test_sender_from_is_none_without_key(self):
        self.assertIsNone(push.sender_from(self.data))
        self.service_account()
        self.assertIsInstance(push.sender_from(self.data), push.FcmSender)


class DeliverTests(PushTestCase):
    def test_fresh_alert_sent_once(self):
        sender = FakeSender()
        with connect(self.data) as db, db:
            self.register(db)
            self.alert(db, NOW - timedelta(minutes=1))
            self.assertEqual(push.deliver(db, NOW, sender),
                             {"sent": 1, "expired": 0, "failed": 0, "pending": 0})
            self.assertEqual([row["state"] for row in self.outbox(db)], ["sent"])
        self.assertEqual(len(sender.calls), 1)
        token, data = sender.calls[0]
        self.assertEqual(token, "tok-1")
        self.assertEqual(data["quiet"], "0")
        with connect(self.data) as db, db:
            self.assertEqual(push.deliver(db, NOW, sender)["sent"], 0)
        self.assertEqual(len(sender.calls), 1)

    def test_eleven_minute_old_alert_expires_unsent(self):
        sender = FakeSender()
        with connect(self.data) as db, db:
            self.register(db)
            self.alert(db, NOW - timedelta(minutes=11))
            counts = push.deliver(db, NOW, sender)
            self.assertEqual(counts["expired"], 1)
            self.assertEqual([row["state"] for row in self.outbox(db)], ["expired"])
        self.assertEqual(len(sender.calls), 0)

    def test_alert_before_registration_never_enqueued(self):
        sender = FakeSender()
        with connect(self.data) as db, db:
            self.register(db, at=NOW - timedelta(hours=1))
            self.alert(db, NOW - timedelta(hours=2))
            push.deliver(db, NOW, sender)
            self.assertEqual(self.outbox(db), [])
        self.assertEqual(len(sender.calls), 0)

    def test_no_sender_stays_pending_then_expires(self):
        with connect(self.data) as db, db:
            self.register(db)
            self.alert(db, NOW - timedelta(minutes=1))
            self.assertEqual(push.deliver(db, NOW, None),
                             {"sent": 0, "expired": 0, "failed": 0, "pending": 1})
            self.assertEqual(json.loads(db.execute("SELECT value FROM meta WHERE key='source:push'").fetchone()[0])["enabled"],
                             False)
        with connect(self.data) as db, db:
            counts = push.deliver(db, NOW + timedelta(minutes=10, seconds=1), None)
            self.assertEqual(counts, {"sent": 0, "expired": 1, "failed": 0, "pending": 0})
            meta = json.loads(db.execute("SELECT value FROM meta WHERE key='source:push'").fetchone()[0])
            self.assertFalse(meta["enabled"])
            self.assertEqual(meta["at"], push.iso(NOW + timedelta(minutes=10, seconds=1)))

    def test_quiet_at_2330_ottawa_sends_quiet_flag(self):
        sender = FakeSender()
        night = datetime(2026, 10, 20, 3, 30, tzinfo=timezone.utc)  # 23:30 EDT on 19 Oct
        with connect(self.data) as db, db:
            self.register(db)
            self.alert(db, night - timedelta(seconds=30))
            self.assertEqual(push.deliver(db, night, sender)["sent"], 1)
        self.assertEqual([data["quiet"] for _token, data in sender.calls], ["1"])

    def test_quiet_at_noon_ottawa_sends_no_quiet_flag(self):
        sender = FakeSender()
        day = datetime(2026, 10, 19, 16, 0, tzinfo=timezone.utc)  # 12:00 EDT
        with connect(self.data) as db, db:
            self.register(db)
            self.alert(db, day - timedelta(seconds=30))
            self.assertEqual(push.deliver(db, day, sender)["sent"], 1)
        self.assertEqual([data["quiet"] for _token, data in sender.calls], ["0"])

    def test_gone_device_removed_with_outbox(self):
        sender = FakeSender((False, "HTTP 404: UNREGISTERED", True))
        with connect(self.data) as db, db:
            self.register(db)
            self.alert(db, NOW - timedelta(minutes=1))
            push.deliver(db, NOW, sender)
            self.assertEqual(db.execute("SELECT count(*) FROM push_devices").fetchone()[0], 0)
            self.assertEqual(self.outbox(db), [])

    def test_failing_sender_marks_failed_after_three_attempts(self):
        sender = FakeSender((False, "HTTP 500: boom", False))
        with connect(self.data) as db, db:
            self.register(db)
            self.alert(db, NOW - timedelta(minutes=1))
            for attempt in (1, 2):
                counts = push.deliver(db, NOW, sender)
                self.assertEqual((counts["failed"], self.outbox(db)[0]["state"], self.outbox(db)[0]["attempts"]),
                                 (0, "pending", attempt))
            counts = push.deliver(db, NOW, sender)
            self.assertEqual((counts["failed"], self.outbox(db)[0]["state"], self.outbox(db)[0]["attempts"]),
                             (1, "failed", 3))
            push.deliver(db, NOW, sender)
        self.assertEqual(len(sender.calls), 3)

    def test_one_bad_device_does_not_stop_others(self):
        class Mixed(FakeSender):
            def send(self, token, data):
                self.calls.append(token)
                if token == "bad":
                    raise RuntimeError("boom")
                return True, None, False
        sender = Mixed()
        with connect(self.data) as db, db:
            self.register(db, device="a", token="bad")
            self.register(db, device="b", token="good")
            self.alert(db, NOW - timedelta(minutes=1))
            counts = push.deliver(db, NOW, sender)
            self.assertEqual((counts["sent"], counts["pending"]), (1, 1))
        self.assertEqual(sorted(sender.calls), ["bad", "good"])

    def test_dry_run_cli_prints_and_changes_nothing(self):
        with connect(self.data) as db, db:
            self.register(db)
            self.alert(db, NOW - timedelta(minutes=1))
        out = io.StringIO()
        with redirect_stdout(out):
            self.assertEqual(push.main(["deliver", "--data", str(self.data), "--dry-run"]), 0)
        self.assertIn('"device": "dev1"', out.getvalue())
        self.assertIn('"sent": 1', out.getvalue())
        with connect(self.data) as db:
            self.assertEqual(self.outbox(db), [])


class PushApiTests(unittest.TestCase):
    def setUp(self):
        from watch.api import make_server
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.data = Path(self.temp.name)
        server = make_server(self.data, "127.0.0.1", 0, clock=lambda: NOW)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()

        def close():
            server.shutdown()
            server.server_close()
            thread.join()
        self.addCleanup(close)
        self.server = server

    def request(self, path, method="GET", value=None, token=True):
        headers = {}
        if token is True:
            headers["Authorization"] = "Bearer " + (self.data / "token").read_text()
        body = json.dumps(value).encode() if value is not None else None
        conn = http.client.HTTPConnection("127.0.0.1", self.server.server_port, timeout=3)
        conn.request(method, path, body, headers)
        response = conn.getresponse()
        result = response.status, json.loads(response.read())
        conn.close()
        return result

    def test_register_requires_token_and_validates_channel(self):
        body = {"channel": "fcm", "token": "tok-1", "device": "dev1"}
        self.assertEqual(self.request("/api/push/register", "POST", body, token=False)[0], 401)
        self.assertEqual(self.request("/api/push/register", "POST", dict(body, channel="sms")), (400, {"error": "channel must be fcm"}))
        self.assertEqual(self.request("/api/push/register", "POST", body), (200, {"ok": True}))
        with connect(self.data) as db:
            self.assertEqual(tuple(db.execute("SELECT device, channel, token FROM push_devices").fetchone()),
                             ("dev1", "fcm", "tok-1"))

    def test_alerts_oldest_first_exact_keys_and_since(self):
        with connect(self.data) as db, db:
            add_alert(db, dict(at="2026-10-19T15:02:40Z", kind="bill_vote", follow="f_bill_c37",
                               title="Vote called on Bill C-37", body="Third reading. Members are being called in.",
                               video={"event": "45901", "offset_s": 4410.0, "live": True}, division=None), "d1")
            add_alert(db, dict(at="2026-10-19T14:00:00Z", kind="mp_speaking", follow="f_abc234",
                               title="Early", body="x", video=None, division=None), "d0")
        status, alerts = self.request("/api/alerts?since=2026-10-19T13:00:00Z")
        self.assertEqual(status, 200)
        self.assertEqual([a["title"] for a in alerts], ["Early", "Vote called on Bill C-37"])
        self.assertEqual(set(alerts[1]), {"id", "at", "kind", "follow", "title", "body", "video", "division"})
        self.assertEqual(alerts[1]["video"], {"event": "45901", "offset_s": 4410.0, "live": True})
        self.assertEqual(self.request("/api/alerts?since=2026-10-19T14:00:00Z")[1][0]["title"],
                         "Vote called on Bill C-37")
        self.assertEqual(self.request("/api/alerts?since=nonsense")[0], 400)

    def test_health_push_source_and_delete(self):
        self.assertEqual(self.request("/api/push/register", "POST", {"channel": "fcm", "token": "tok-1", "device": "dev1"}),
                         (200, {"ok": True}))
        self.assertNotIn("push", self.request("/api/health")[1]["sources"])
        with connect(self.data) as db, db:
            push.deliver(db, NOW, None)
        self.assertEqual(self.request("/api/health")[1]["sources"]["push"],
                         {"at": "2026-10-19T16:00:00Z", "ok": True, "error": None, "enabled": False})
        self.assertEqual(self.request("/api/push/register?device=dev1", "DELETE", token=False)[0], 401)
        self.assertEqual(self.request("/api/push/register?device=dev1", "DELETE"), (200, {"ok": True}))
        self.assertEqual(self.request("/api/push/register?device=dev1", "DELETE"), (200, {"ok": True}))
        with connect(self.data) as db:
            self.assertEqual(db.execute("SELECT count(*) FROM push_devices").fetchone()[0], 0)


if __name__ == "__main__":
    unittest.main()
