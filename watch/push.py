"""Push alerts to registered devices through Firebase Cloud Messaging (HTTP v1), data-only.

The key file `<data>/fcm-service-account.json` turns push on; without it alerts stay pending
and expire. `python3 -m watch.push deliver --data DIR [--dry-run]` sends one round."""

import argparse
from datetime import datetime, time, timedelta, timezone
import base64
import json
import os
from pathlib import Path
import subprocess
import tempfile
import urllib.error
import urllib.request

from watch.digest import OTTAWA
from watch.store import DEFAULT_DATA, connect, iso, set_meta


QUIET_START, QUIET_END = time(22, 0), time(8, 0)
OPENSSL = "/usr/bin/openssl"
SCOPE = "https://www.googleapis.com/auth/firebase.messaging"
SEND_URL = "https://fcm.googleapis.com/v1/projects/%s/messages:send"
MAX_ATTEMPTS = 3
EXPIRE_AFTER = timedelta(minutes=10)


def is_quiet(at_utc):
    """True from 22:00 up to 08:00 Ottawa time."""
    now = at_utc.astimezone(OTTAWA).time()
    return now >= QUIET_START or now < QUIET_END


def register(db, body, now):
    if not isinstance(body, dict) or body.get("channel") != "fcm":
        raise ValueError("channel must be fcm")
    token, device = body.get("token"), body.get("device")
    if not isinstance(token, str) or not token or len(token) > 4096:
        raise ValueError("token required (at most 4096 characters)")
    if not isinstance(device, str) or not device or len(device) > 200:
        raise ValueError("device required (at most 200 characters)")
    db.execute("INSERT INTO push_devices(device,channel,token,registered_at,last_error) VALUES (?,?,?,?,NULL) "
               "ON CONFLICT(device) DO UPDATE SET channel=excluded.channel, token=excluded.token, "
               "registered_at=excluded.registered_at, last_error=NULL",
               (device, "fcm", token, iso(now)))


def unregister(db, device):
    db.execute("DELETE FROM push_outbox WHERE device=?", (device,))
    db.execute("DELETE FROM push_devices WHERE device=?", (device,))


def message(alert, quiet):
    return {"type": "alert", "alert": json.dumps(alert, separators=(",", ":"), sort_keys=True),
            "quiet": "1" if quiet else "0"}


def fcm_body(token, data):
    return {"message": {"token": token, "data": data, "android": {"priority": "high", "ttl": "600s"}}}


def _b64(raw):
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode("ascii")


def _urllib_transport(url, body, headers):
    request = urllib.request.Request(url, data=body, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read()


class FcmSender:
    def __init__(self, key_path, transport=None, clock=None):
        key = json.loads(Path(key_path).read_text())
        self.project_id = key["project_id"]
        self.client_email = key["client_email"]
        self.private_key = key["private_key"]
        self.token_uri = key["token_uri"]
        self.transport = transport or _urllib_transport
        self.clock = clock or (lambda: datetime.now(timezone.utc))
        self._token = None
        self._expires = 0.0

    def _sign(self, signing_input):
        # The key goes to a 0600 file in a private temp dir, removed as soon as openssl has run.
        with tempfile.TemporaryDirectory() as tmp:
            keyfile = Path(tmp) / "key.pem"
            fd = os.open(keyfile, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(fd, "w") as handle:
                handle.write(self.private_key)
            result = subprocess.run([OPENSSL, "dgst", "-sha256", "-sign", str(keyfile)],
                                    input=signing_input, capture_output=True, check=True)
        return result.stdout

    def access_token(self):
        now = int(self.clock().timestamp())
        if self._token and now < self._expires:
            return self._token
        header = _b64(json.dumps({"alg": "RS256", "typ": "JWT"}, separators=(",", ":")).encode())
        claims = {"iss": self.client_email, "scope": SCOPE, "aud": self.token_uri,
                  "iat": now, "exp": now + 3600}
        signing_input = header + "." + _b64(json.dumps(claims, separators=(",", ":")).encode())
        assertion = signing_input + "." + _b64(self._sign(signing_input.encode("ascii")))
        form = "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=" + assertion
        status, body = self.transport(self.token_uri, form.encode("ascii"),
                                      {"Content-Type": "application/x-www-form-urlencoded"})
        if status != 200:
            raise RuntimeError("token exchange failed: HTTP %d" % status)
        found = json.loads(body)
        self._token = found["access_token"]
        self._expires = now + int(found["expires_in"]) - 60
        return self._token

    def send(self, token, data):
        try:
            access = self.access_token()
            url = SEND_URL % self.project_id
            status, body = self.transport(url, json.dumps(fcm_body(token, data)).encode(),
                                          {"Authorization": "Bearer " + access,
                                           "Content-Type": "application/json"})
        except Exception as exc:
            return False, str(exc), False
        if status == 200:
            return True, None, False
        text = body.decode("utf-8", "replace")
        return False, "HTTP %d: %s" % (status, text[:300]), status == 404 or "UNREGISTERED" in text


class DryRunSender:
    """Prints what would be sent; never touches the network."""

    def __init__(self, devices):
        self.devices = devices

    def send(self, token, data):
        print(json.dumps({"device": self.devices.get(token), "data": data}, sort_keys=True))
        return True, None, False


def sender_from(data_dir):
    key = Path(data_dir).expanduser() / "fcm-service-account.json"
    return FcmSender(key) if key.exists() else None


def _parse(value):
    return datetime.fromisoformat(value)


def _enqueue(db):
    alerts = [(row["id"], _parse(row["at"])) for row in db.execute("SELECT id, at FROM alerts")]
    for device in db.execute("SELECT device, registered_at FROM push_devices").fetchall():
        registered = _parse(device["registered_at"])
        for alert_id, at in alerts:
            if at >= registered:
                db.execute("INSERT OR IGNORE INTO push_outbox(alert,device,state) VALUES (?,?,'pending')",
                           (alert_id, device["device"]))


def deliver(db, now, sender):
    _enqueue(db)
    counts = dict(sent=0, expired=0, failed=0, pending=0)
    error = None
    gone = set()
    rows = db.execute(
        "SELECT o.alert, o.device, o.attempts, a.at, a.kind, a.title, a.body, a.video, a.division, "
        "a.follow, a.id, d.token FROM push_outbox o "
        "JOIN alerts a ON a.id=o.alert JOIN push_devices d ON d.device=o.device "
        "WHERE o.state='pending' ORDER BY a.at, a.id").fetchall()
    for row in rows:
        if row["device"] in gone:
            continue
        if now - _parse(row["at"]) > EXPIRE_AFTER:
            db.execute("UPDATE push_outbox SET state='expired' WHERE alert=? AND device=?",
                       (row["alert"], row["device"]))
            counts["expired"] += 1
            continue
        if sender is None:
            continue
        alert = dict(id=row["id"], at=row["at"], kind=row["kind"], follow=row["follow"],
                     title=row["title"], body=row["body"],
                     video=None if row["video"] is None else json.loads(row["video"]),
                     division=None if row["division"] is None else json.loads(row["division"]))
        quiet = is_quiet(now) or is_quiet(_parse(row["at"]))
        try:
            ok, send_error, device_gone = sender.send(row["token"], message(alert, quiet))
        except Exception as exc:
            ok, send_error, device_gone = False, str(exc), False
        if ok:
            db.execute("UPDATE push_outbox SET state='sent', sent_at=? WHERE alert=? AND device=?",
                       (iso(now), row["alert"], row["device"]))
            db.execute("UPDATE push_devices SET last_error=NULL WHERE device=?", (row["device"],))
            counts["sent"] += 1
        elif device_gone:
            unregister(db, row["device"])
            gone.add(row["device"])
        else:
            attempts = row["attempts"] + 1
            state = "failed" if attempts >= MAX_ATTEMPTS else "pending"
            db.execute("UPDATE push_outbox SET attempts=?, error=?, state=? WHERE alert=? AND device=?",
                       (attempts, send_error, state, row["alert"], row["device"]))
            db.execute("UPDATE push_devices SET last_error=? WHERE device=?", (send_error, row["device"]))
            if state == "failed":
                counts["failed"] += 1
            error = send_error
    counts["pending"] = db.execute("SELECT count(*) FROM push_outbox WHERE state='pending'").fetchone()[0]
    set_meta(db, "source:push", json.dumps({"at": iso(now), "ok": error is None, "error": error,
                                            "enabled": sender is not None}))
    return counts


def main(argv=None):
    parser = argparse.ArgumentParser(description="Push Parliament watch alerts")
    commands = parser.add_subparsers(dest="command", required=True)
    run = commands.add_parser("deliver", help="send pending alerts once")
    run.add_argument("--data", default=DEFAULT_DATA)
    run.add_argument("--dry-run", action="store_true", help="print what would be sent; change nothing")
    args = parser.parse_args(argv)
    now = datetime.now(timezone.utc)
    with connect(args.data) as db:
        if args.dry_run:
            devices = {row[0]: row[1] for row in db.execute("SELECT token, device FROM push_devices")}
            counts = deliver(db, now, DryRunSender(devices))
            db.rollback()
        else:
            counts = deliver(db, now, sender_from(args.data))
            db.commit()
    print(json.dumps(counts, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
