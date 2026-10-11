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
CREATE TABLE IF NOT EXISTS vectors (
 paragraph TEXT PRIMARY KEY, model TEXT NOT NULL, vec BLOB NOT NULL);
CREATE TABLE IF NOT EXISTS follow_vectors (
 follow TEXT NOT NULL, lang TEXT NOT NULL, phrase TEXT NOT NULL,
 model TEXT NOT NULL, vec BLOB NOT NULL, PRIMARY KEY (follow, lang));
CREATE TABLE IF NOT EXISTS matches (
 follow TEXT NOT NULL, item_kind TEXT NOT NULL, item_id TEXT NOT NULL,
 score REAL NOT NULL, at TEXT NOT NULL, PRIMARY KEY (follow, item_kind, item_id));
CREATE INDEX IF NOT EXISTS matches_at ON matches (at);
"""


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
        yield db
    finally:
        db.close()


def set_meta(db, key, value):
    db.execute("INSERT INTO meta VALUES (?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
               (key, value))


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
