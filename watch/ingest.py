"""Pure source parsers and a small injectable fetch/SQLite ingest layer."""

import argparse
from datetime import datetime, timezone
import gzip
import hashlib
import json
from pathlib import Path
import sys
from urllib.request import Request, urlopen
import xml.etree.ElementTree as ET

from watch.store import DEFAULT_DATA, connect, iso, set_meta


USER_AGENT = "ParTake/0.1 (+https://github.com/noamvb/ParTake; personal, non-commercial)"
URLS = {
    "members": "https://www.ourcommons.ca/Members/en/search/XML",
    "ministries": "https://www.ourcommons.ca/Members/en/ministries/XML",
    "bills": "https://www.parl.ca/legisinfo/en/bills/json",
}


def _xml_rows(body, root_name, row_name):
    root = ET.fromstring(body)
    if root.tag != root_name:
        raise ValueError("unexpected XML root")
    return root.findall(row_name)


def _text(row, key):
    child = row.find(key)
    if child is None or child.text is None:
        raise ValueError("missing " + key)
    return child.text


def parse_members(body):
    result = []
    for row in _xml_rows(body, "ArrayOfMemberOfParliament", "MemberOfParliament"):
        first, last = _text(row, "PersonOfficialFirstName"), _text(row, "PersonOfficialLastName")
        result.append((_text(row, "PersonId"), first + " " + last, _text(row, "CaucusShortName"),
                       _text(row, "ConstituencyName"), _text(row, "ConstituencyProvinceTerritoryName"), first, last))
    return result


def parse_ministries(body):
    result = []
    for row in _xml_rows(body, "ArrayOfMinister", "Minister"):
        end = row.find("ToDateTime")
        if end is not None and end.get("{http://www.w3.org/2001/XMLSchema-instance}nil") == "true":
            result.append((_text(row, "PersonId"), _text(row, "Title"), int(_text(row, "OrderOfPrecedence"))))
    return result


def parse_bills(body):
    values = json.loads(body)
    if not isinstance(values, list):
        raise ValueError("bills must be a list")
    return [(f'{b["ParliamentNumber"]}-{b["SessionNumber"]}/{b["NumberCode"]}',
             b["NumberCode"], b["ShortTitleEn"] or b["LongTitleEn"], b["StatusNameEn"], None) for b in values]


def fetch(url):
    with urlopen(Request(url, headers={"User-Agent": USER_AGENT}), timeout=30) as response:
        return response.read()


def store_raw(data_dir, source, body, now, key=None):
    if source not in set(URLS) | {"votes", "ballots", "hansard", "evidence", "meetings", "committees", "evidence_pages"}:
        raise ValueError("unknown source")
    digest = hashlib.sha256(body).hexdigest()
    with connect(data_dir) as db, db:
        db.execute("BEGIN IMMEDIATE")
        key = "raw:" + (source if key is None else key)
        previous = db.execute("SELECT value FROM meta WHERE key=?", (key,)).fetchone()
        if previous and previous[0] == digest:
            return
        at = iso(now)
        path = Path(data_dir).expanduser() / "raw" / source / (at[:10] + ".jsonl.gz")
        path.parent.mkdir(parents=True, exist_ok=True)
        record = {"at": at, "sha256": digest, "body": body.decode("utf-8-sig")}
        with gzip.open(path, "at", encoding="utf-8") as raw:
            raw.write(json.dumps(record, ensure_ascii=False) + "\n")
        set_meta(db, key, digest)


def ingest_source(data_dir, source, fetch=fetch, now=None):
    now = now or datetime.now(timezone.utc)
    try:
        body = fetch(URLS[source])
        store_raw(data_dir, source, body, now)
        rows = {"members": parse_members, "ministries": parse_ministries, "bills": parse_bills}[source](body)
        with connect(data_dir) as db, db:
            db.execute("BEGIN IMMEDIATE")
            db.execute("DELETE FROM " + source)
            marks = {"members": "?,?,?,?,?,?,?", "ministries": "?,?,?", "bills": "?,?,?,?,?"}[source]
            db.executemany("INSERT INTO " + source + " VALUES (" + marks + ")", rows)
            if source == "bills":
                from watch.records import parse_bill_stages
                stages = parse_bill_stages(body)
                db.execute("CREATE TEMP TABLE current_stages (bill TEXT, stage TEXT, chamber TEXT)")
                for stage in stages:
                    db.execute("INSERT INTO bill_stages(bill,stage,chamber,at) VALUES (:bill,:stage,:chamber,:at) "
                               "ON CONFLICT(bill,stage,chamber) DO UPDATE SET at=excluded.at", stage)
                    db.execute("INSERT INTO current_stages VALUES (:bill,:stage,:chamber)", stage)
                db.execute("DELETE FROM bill_stages WHERE NOT EXISTS (SELECT 1 FROM current_stages c "
                           "WHERE c.bill=bill_stages.bill AND c.stage=bill_stages.stage AND c.chamber=bill_stages.chamber)")
                db.execute("UPDATE bills SET stage_at=(SELECT max(at) FROM bill_stages WHERE bill=bills.id)")
            set_meta(db, "source:" + source, json.dumps({"at": iso(now), "ok": True, "error": None}))
        return True
    except Exception as exc:
        with connect(data_dir) as db, db:
            set_meta(db, "source:" + source, json.dumps({"at": iso(now), "ok": False, "error": str(exc) or type(exc).__name__}))
        return False


def main(argv=None):
    parser = argparse.ArgumentParser(description="Refresh Parliament watch lookups")
    parser.add_argument("--data", default=DEFAULT_DATA)
    args = parser.parse_args(argv)
    outcomes = [ingest_source(args.data, source) for source in URLS]
    for source, ok in zip(URLS, outcomes):
        sys.stderr.write("%s %s\n" % (source, "ok" if ok else "failed"))
    return 0 if all(outcomes) else 1


if __name__ == "__main__":
    sys.exit(main())
