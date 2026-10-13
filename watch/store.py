"""SQLite storage, follow validation and transactional list replacement."""

from contextlib import contextmanager
from datetime import timezone
import json
from pathlib import Path
import secrets
import sqlite3


DEFAULT_DATA = "~/.local/share/partake-watch"
KIND_KEYS = ("topic", "bill", "mp", "votes", "committee")
KINDS = set(KIND_KEYS) | {"house", "pm-qp"}
SCHEMA = """
CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT);
INSERT OR IGNORE INTO meta VALUES ('version', '0');
CREATE TABLE IF NOT EXISTS members (
 person_id TEXT PRIMARY KEY, name TEXT, party TEXT, riding TEXT, province TEXT,
 first_name TEXT, last_name TEXT);
CREATE TABLE IF NOT EXISTS ministries (
 person_id TEXT, title TEXT, precedence INTEGER);
CREATE TABLE IF NOT EXISTS bills (
 id TEXT PRIMARY KEY, number TEXT, title TEXT, stage TEXT, stage_at TEXT);
CREATE TABLE IF NOT EXISTS follows (
 seq INTEGER PRIMARY KEY AUTOINCREMENT, id TEXT UNIQUE NOT NULL,
 created_at TEXT NOT NULL, body TEXT NOT NULL, removed_at TEXT);
CREATE TABLE IF NOT EXISTS bill_stages (
 id INTEGER PRIMARY KEY, bill TEXT NOT NULL, stage TEXT NOT NULL,
 chamber TEXT NOT NULL, at TEXT NOT NULL, UNIQUE (bill, stage, chamber));
CREATE TABLE IF NOT EXISTS divisions (
 id TEXT PRIMARY KEY, number INTEGER NOT NULL, at TEXT NOT NULL, bill TEXT,
 description TEXT NOT NULL, result TEXT NOT NULL,
 yeas INTEGER NOT NULL, nays INTEGER NOT NULL, paired INTEGER NOT NULL,
 ballots_loaded INTEGER NOT NULL DEFAULT 0);
CREATE TABLE IF NOT EXISTS ballots (
 division TEXT NOT NULL, person_id TEXT NOT NULL, party TEXT NOT NULL,
 vote TEXT NOT NULL, PRIMARY KEY (division, person_id));
CREATE TABLE IF NOT EXISTS committees (slug TEXT PRIMARY KEY, acronym TEXT);
CREATE TABLE IF NOT EXISTS affiliations (db_id TEXT PRIMARY KEY, person_id TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS documents (
 id TEXT PRIMARY KEY, source TEXT NOT NULL, session TEXT NOT NULL,
 number INTEGER NOT NULL, committee TEXT, date TEXT NOT NULL,
 url TEXT NOT NULL, fetched_at TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS paragraphs (
 seq INTEGER PRIMARY KEY AUTOINCREMENT, id TEXT UNIQUE NOT NULL,
 document TEXT NOT NULL, intervention TEXT NOT NULL, position INTEGER NOT NULL,
 at TEXT NOT NULL, title TEXT NOT NULL, lang TEXT NOT NULL,
 text_en TEXT NOT NULL, text_fr TEXT NOT NULL,
 speaker TEXT, person_id TEXT, source TEXT NOT NULL,
 event_id TEXT, offset_s REAL, confidence REAL);
CREATE INDEX IF NOT EXISTS paragraphs_at ON paragraphs (at);
CREATE INDEX IF NOT EXISTS paragraphs_person ON paragraphs (person_id);
CREATE INDEX IF NOT EXISTS paragraphs_document ON paragraphs (document, position);
CREATE INDEX IF NOT EXISTS paragraphs_event ON paragraphs (event_id);
CREATE TABLE IF NOT EXISTS vectors (
 paragraph TEXT PRIMARY KEY, model TEXT NOT NULL, vec BLOB NOT NULL);
CREATE TABLE IF NOT EXISTS follow_vectors (
 follow TEXT NOT NULL, lang TEXT NOT NULL, phrase TEXT NOT NULL,
 model TEXT NOT NULL, vec BLOB NOT NULL, PRIMARY KEY (follow, lang));
CREATE TABLE IF NOT EXISTS matches (
 follow TEXT NOT NULL, item_kind TEXT NOT NULL, item_id TEXT NOT NULL,
 score REAL NOT NULL, at TEXT NOT NULL, PRIMARY KEY (follow, item_kind, item_id));
CREATE INDEX IF NOT EXISTS matches_at ON matches (at);
CREATE TABLE IF NOT EXISTS events (
 id TEXT PRIMARY KEY, title TEXT NOT NULL, kind TEXT NOT NULL, committee TEXT,
 number INTEGER NOT NULL, document TEXT NOT NULL, scheduled_start TEXT NOT NULL,
 actual_start TEXT, actual_end TEXT, status INTEGER NOT NULL, has_archive INTEGER NOT NULL,
 recording_start TEXT, preroll_s REAL, stream_url TEXT, captions TEXT NOT NULL DEFAULT 'none',
 updated_at TEXT NOT NULL);
CREATE INDEX IF NOT EXISTS events_document ON events (document);
CREATE TABLE IF NOT EXISTS captions (
 event TEXT NOT NULL, lang TEXT NOT NULL, source TEXT NOT NULL, seq INTEGER NOT NULL,
 begin TEXT NOT NULL, end TEXT NOT NULL, text TEXT NOT NULL,
 PRIMARY KEY (event, lang, source, seq));
CREATE TABLE IF NOT EXISTS digests (
 id TEXT PRIMARY KEY, date TEXT NOT NULL, kind TEXT NOT NULL, created_at TEXT NOT NULL,
 replaces TEXT, body TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS opinion_polls (
 id TEXT, region TEXT, firm TEXT, end_date TEXT, sample INTEGER, rolling REAL, link TEXT,
 lpc REAL, cpc REAL, ndp REAL, gpc REAL, bq REAL, oth REAL, fetched_at TEXT,
 PRIMARY KEY (id, region));
CREATE TABLE IF NOT EXISTS leader_polls (
 kind TEXT, firm TEXT, end_date TEXT, body TEXT, PRIMARY KEY (kind, firm, end_date));
CREATE TABLE IF NOT EXISTS ridings (
 id TEXT PRIMARY KEY, name_en TEXT, name_fr TEXT, province TEXT, region TEXT);
CREATE TABLE IF NOT EXISTS riding_results (
 riding TEXT, election TEXT, party TEXT, votes INTEGER, elected INTEGER,
 PRIMARY KEY (riding, election, party));
CREATE TABLE IF NOT EXISTS riding_winners (
 riding TEXT, election TEXT, family TEXT, first TEXT, PRIMARY KEY (riding, election));
CREATE TABLE IF NOT EXISTS projections (date TEXT PRIMARY KEY, body TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS riding_projections (
 riding TEXT, date TEXT, shares TEXT NOT NULL, winner TEXT NOT NULL, margin REAL NOT NULL,
 PRIMARY KEY (riding, date));
CREATE TABLE IF NOT EXISTS alerts (
 id TEXT PRIMARY KEY, at TEXT NOT NULL, kind TEXT NOT NULL, follow TEXT NOT NULL,
 dedupe TEXT UNIQUE NOT NULL, title TEXT NOT NULL, body TEXT NOT NULL,
 video TEXT, division TEXT);
CREATE INDEX IF NOT EXISTS alerts_at ON alerts (at);
CREATE TABLE IF NOT EXISTS push_devices (
 device TEXT PRIMARY KEY, channel TEXT NOT NULL, token TEXT NOT NULL,
 registered_at TEXT NOT NULL, last_error TEXT);
CREATE TABLE IF NOT EXISTS push_outbox (
 alert TEXT NOT NULL, device TEXT NOT NULL, state TEXT NOT NULL,
 attempts INTEGER NOT NULL DEFAULT 0, sent_at TEXT, error TEXT,
 PRIMARY KEY (alert, device));
CREATE TABLE IF NOT EXISTS opinion_notes (
 week_of TEXT PRIMARY KEY, text TEXT NOT NULL, created_at TEXT NOT NULL);
"""
# Columns added after a table first shipped; connect() adds any that are missing.
COLUMNS = (("paragraphs", "superseded_by", "TEXT"),
           ("opinion_polls", "first_seen", "TEXT"),
           ("riding_projections", "probs", "TEXT"))


def iso(now):
    return now.astimezone(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def follow_id():
    return "f_" + "".join(secrets.choice("abcdefghijklmnopqrstuvwxyz234567") for _ in range(6))


@contextmanager
def connect(data_dir):
    path = Path(data_dir).expanduser()
    path.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(path / "watch.db", timeout=20)
    db.row_factory = sqlite3.Row
    try:
        db.executescript(SCHEMA)
        for table, column, kind in COLUMNS:
            if column not in {row[1] for row in db.execute("PRAGMA table_info(%s)" % table)}:
                db.execute("ALTER TABLE %s ADD COLUMN %s %s" % (table, column, kind))
                if (table, column) == ("opinion_polls", "first_seen"):
                    # Polls already stored were first seen when they were fetched.
                    db.execute("UPDATE opinion_polls SET first_seen=fetched_at")
                    db.commit()
        yield db
    finally:
        db.close()


def set_meta(db, key, value):
    db.execute("INSERT INTO meta VALUES (?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
               (key, value))


def add_alert(db, alert, dedupe):
    """Store one alert unless its dedupe key exists; return the stored id or None.

    `alert` has the api.md shape without `id`: at, kind, follow, title, body,
    video (dict or None), division (dict or None)."""
    alert_id = "a_" + secrets.token_hex(4)
    cursor = db.execute(
        "INSERT OR IGNORE INTO alerts(id,at,kind,follow,dedupe,title,body,video,division) "
        "VALUES (?,?,?,?,?,?,?,?,?)",
        (alert_id, alert["at"], alert["kind"], alert["follow"], dedupe, alert["title"], alert["body"],
         None if alert.get("video") is None else json.dumps(alert["video"]),
         None if alert.get("division") is None else json.dumps(alert["division"])))
    return alert_id if cursor.rowcount else None


def alert_dict(row):
    """An alerts row as the api.md object."""
    return {"id": row["id"], "at": row["at"], "kind": row["kind"], "follow": row["follow"],
            "title": row["title"], "body": row["body"],
            "video": None if row["video"] is None else json.loads(row["video"]),
            "division": None if row["division"] is None else json.loads(row["division"])}


def list_follows(db):
    return {"version": int(db.execute("SELECT value FROM meta WHERE key='version'").fetchone()[0]),
            "follows": [json.loads(row["body"]) for row in db.execute(
                "SELECT body FROM follows WHERE removed_at IS NULL ORDER BY created_at,seq")]}


class StaleVersion(Exception):
    def __init__(self, current):
        self.current = current


def validate_follow(follow):
    if not isinstance(follow, dict) or follow.get("kind") not in KINDS:
        raise ValueError("unknown kind")
    kind = follow["kind"]
    if not isinstance(follow.get("label"), str) or not follow["label"].strip():
        raise ValueError("label required")
    for key in KIND_KEYS:
        if key != kind and follow.get(key) is not None:
            raise ValueError("kind object mismatch")
    obj = follow.get(kind)
    if kind in ("house", "pm-qp"):
        return
    if not isinstance(obj, dict):
        raise ValueError("kind object required")
    fields = {"bill": ("id", "number", "title"),
              "mp": ("person_id", "name", "party", "riding"),
              "committee": ("code",), "votes": ("filter",)}
    if kind in fields:
        if any(not isinstance(obj.get(key), str) for key in fields[kind]):
            raise ValueError("required kind fields")
    if kind == "votes" and obj["filter"] not in ("all", "party_split"):
        raise ValueError("invalid votes filter")
    if kind == "topic":
        phrases = obj.get("phrases")
        if not isinstance(phrases, dict) or any(not isinstance(phrases.get(k), str) for k in ("en", "fr")):
            raise ValueError("phrases required")
        if not isinstance(obj.get("keywords"), list) or any(not isinstance(k, str) for k in obj["keywords"]):
            raise ValueError("keywords required")
        threshold = obj.get("threshold")
        if type(threshold) not in (int, float) or not 0.0 <= threshold <= 1.0:
            raise ValueError("invalid threshold")


def _validate_list(follows, current):
    if not isinstance(follows, list):
        raise ValueError("follows must be a list")
    current_ids = {f["id"] for f in current["follows"]}
    seen_ids = set()
    unique = set()
    for follow in follows:
        validate_follow(follow)
        if "id" in follow:
            fid = follow["id"]
            if not isinstance(fid, str) or fid not in current_ids or fid in seen_ids:
                raise ValueError("invalid follow id")
            seen_ids.add(fid)
        kind = follow["kind"]
        key = (kind, follow["committee"]["code"]) if kind == "committee" else (kind,)
        if kind in ("house", "pm-qp", "committee"):
            if key in unique:
                raise ValueError("duplicate follow")
            unique.add(key)


def _write_list(db, follows, current, clock, new_id):
    existing = {f["id"]: f for f in current["follows"]}
    result = []
    for follow in follows:
        item = {key: follow.get(key) for key in KIND_KEYS}
        item.update(kind=follow["kind"], label=follow["label"])
        if "id" in follow:
            item.update(id=follow["id"], created_at=existing[follow["id"]]["created_at"])
            db.execute("UPDATE follows SET body=? WHERE id=?", (json.dumps(item), item["id"]))
        else:
            fid = new_id()
            while db.execute("SELECT 1 FROM follows WHERE id=?", (fid,)).fetchone():
                fid = new_id()
            item.update(id=fid, created_at=iso(clock()))
            db.execute("INSERT INTO follows(id,created_at,body) VALUES (?,?,?)",
                       (fid, item["created_at"], json.dumps(item)))
        result.append(item)
    kept = {f["id"] for f in result}
    removed = [f["id"] for f in current["follows"] if f["id"] not in kept]
    if removed:
        removed_at = iso(clock())
        db.executemany("UPDATE follows SET removed_at=? WHERE id=?", [(removed_at, fid) for fid in removed])
    set_meta(db, "version", str(current["version"] + 1))
    return list_follows(db)


def replace_follows(data_dir, body, clock, new_id):
    if not isinstance(body, dict) or type(body.get("version")) is not int:
        raise ValueError("version required")
    with connect(data_dir) as db, db:
        db.execute("BEGIN IMMEDIATE")
        current = list_follows(db)
        if body["version"] != current["version"]:
            raise StaleVersion(current)
        follows = body.get("follows")
        _validate_list(follows, current)
        return _write_list(db, follows, current, clock, new_id)


def import_follows(data_dir, body, clock, new_id):
    if not isinstance(body, dict) or not isinstance(body.get("keys"), list):
        raise ValueError("keys required")
    if any(not isinstance(key, str) or not key.strip() for key in body["keys"]):
        raise ValueError("invalid import key")
    with connect(data_dir) as db, db:
        db.execute("BEGIN IMMEDIATE")
        current = list_follows(db)
        follows = list(current["follows"])
        for key in body["keys"]:
            kind, label = {
                "HOC": ("house", "House of Commons (chamber)"),
                "PM-QP": ("pm-qp", "Prime Minister at Question Period"),
            }.get(key, ("committee", key))
            if any(f["kind"] == kind and (kind != "committee" or f["committee"]["code"] == key) for f in follows):
                continue
            item = {"kind": kind, "label": label}
            if kind == "committee":
                item["committee"] = {"code": key}
            follows.append(item)
        if len(follows) == len(current["follows"]):
            return current
        _validate_list(follows, current)
        return _write_list(db, follows, current, clock, new_id)
