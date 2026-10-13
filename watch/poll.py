"""Incremental Parliament record polling with injectable network and pacing."""

import argparse
from datetime import datetime, timezone
from html.parser import HTMLParser
import json
import re
import sys
from time import sleep
from urllib.error import HTTPError
from urllib.parse import urljoin

from watch.ingest import fetch, ingest_source, store_raw
from watch.records import SESSION, SpeakerIndex, parse_ballots, parse_divisions, parse_transcript
from watch.store import DEFAULT_DATA, connect, iso, set_meta


COMMONS = "https://www.ourcommons.ca"
OPENPARLIAMENT = "https://api.openparliament.ca"
VOTES = COMMONS + "/Members/en/votes/"


def _status(data_dir, source, now, error=None):
    with connect(data_dir) as db, db:
        set_meta(db, "source:" + source, json.dumps(dict(at=iso(now), ok=error is None, error=error)))
    return error is None


def _save_transcript(data_dir, en, fr, source, number, committee, now):
    document, paragraphs = parse_transcript(en, fr, source=source, number=number, committee=committee)
    with connect(data_dir) as db, db:
        db.execute("BEGIN IMMEDIATE")
        index = SpeakerIndex(db.execute("SELECT * FROM members"), db.execute("SELECT * FROM ministries"))
        cache = dict(db.execute("SELECT db_id,person_id FROM affiliations"))
        for paragraph in paragraphs:
            person = index.resolve(paragraph["speaker"], paragraph["db_id"], cache)
            paragraph.update(person_id=person, confidence=1.0 if person is not None else None)
        db.executemany("INSERT INTO affiliations VALUES (?,?) ON CONFLICT(db_id) DO UPDATE SET person_id=excluded.person_id", cache.items())
        document["fetched_at"] = iso(now)
        db.execute("INSERT INTO documents VALUES (:id,:source,:session,:number,:committee,:date,:url,:fetched_at)", document)
        db.executemany("INSERT INTO paragraphs(id,document,intervention,position,at,title,lang,text_en,text_fr,speaker,person_id,source,confidence) "
                       "VALUES (:id,:document,:intervention,:position,:at,:title,:lang,:text_en,:text_fr,:speaker,:person_id,:source,:confidence)", paragraphs)


def poll_hansard(data_dir, fetch, sleep, now, max_docs=None):
    try:
        with connect(data_dir) as db:
            number = db.execute("SELECT coalesce(max(number),0)+1 FROM documents WHERE source='hansard' AND session=?", (SESSION,)).fetchone()[0]
        count = 0
        while max_docs is None or count < max_docs:
            url = COMMONS + f"/Content/House/451/Debates/{number:03d}/HAN{number:03d}-E.XML"
            try:
                en, fr = fetch(url), fetch(url.replace("-E.XML", "-F.XML"))
            except HTTPError as exc:
                if exc.code == 404:
                    break
                raise
            for lang, body in (("E", en), ("F", fr)):
                store_raw(data_dir, "hansard", body, now, key=f"hansard/{number}-{lang}")
            _save_transcript(data_dir, en, fr, "hansard", number, None, now)
            count += 1
            number += 1
            if max_docs is None or count < max_docs:
                sleep(1.0)
        return _status(data_dir, "hansard", now)
    except Exception as exc:
        return _status(data_dir, "hansard", now, str(exc) or type(exc).__name__)


class _EvidenceLink(HTMLParser):
    def __init__(self):
        super().__init__()
        self.url = None

    def handle_starttag(self, tag, attrs):
        href = dict(attrs).get("href", "")
        if self.url is None and href.endswith("-E.XML"):
            self.url = urljoin(COMMONS, href)


def poll_evidence(data_dir, fetch, sleep, now, max_docs=None):
    count, fetched = 0, False

    def get(url, source, key):
        nonlocal fetched
        if fetched:
            sleep(1.0)
        fetched = True
        body = fetch(url)
        store_raw(data_dir, source, body, now, key=key)
        return body

    try:
        url = OPENPARLIAMENT + "/committees/meetings/?format=json&limit=500"
        while url and (max_docs is None or count < max_docs):
            page = json.loads(get(url, "meetings", url))
            all_stored = True
            for meeting in page["objects"]:
                match = re.fullmatch(r"/committees/([^/]+)/45-1/(\d+)/", meeting["url"])
                if not meeting.get("has_evidence") or not match:
                    continue
                slug, number = match.group(1), int(match.group(2))
                with connect(data_dir) as db:
                    committee = db.execute("SELECT acronym FROM committees WHERE slug=?", (slug,)).fetchone()
                    stored = committee and db.execute("SELECT 1 FROM documents WHERE id=?", (f"evidence/{SESSION}/{committee[0]}/{number}",)).fetchone()
                if stored:
                    continue
                if committee is not None and committee[0] is None:
                    continue
                all_stored = False
                if committee is None:
                    info = json.loads(get(OPENPARLIAMENT + f"/committees/{slug}/?format=json", "committees", slug))
                    acronym = next((s.get("acronym") for s in info["sessions"] if s["session"] == SESSION), None)
                    with connect(data_dir) as db, db:
                        db.execute("INSERT INTO committees VALUES (?,?)", (slug, acronym))
                else:
                    acronym = committee[0]
                if acronym is None:
                    continue
                page_url = COMMONS + f"/DocumentViewer/en/{SESSION}/{acronym}/meeting-{number}/evidence"
                link = _EvidenceLink()
                link.feed(get(page_url, "evidence_pages", page_url).decode("utf-8-sig"))
                if link.url is None:
                    continue
                key = f"evidence/{acronym}/{number}"
                en = get(link.url, "evidence", key + "-E")
                fr = get(link.url.replace("-E.XML", "-F.XML"), "evidence", key + "-F")
                _save_transcript(data_dir, en, fr, "evidence", number, acronym, now)
                count += 1
                if max_docs is not None and count >= max_docs:
                    break
            if all_stored:
                break
            next_url = page.get("pagination", {}).get("next_url")
            url = urljoin(OPENPARLIAMENT, next_url) if next_url else None
        return _status(data_dir, "evidence", now)
    except Exception as exc:
        return _status(data_dir, "evidence", now, str(exc) or type(exc).__name__)


def poll_votes(data_dir, fetch, sleep, now):
    error = None
    try:
        body = fetch(VOTES + "xml")
        store_raw(data_dir, "votes", body, now)
        with connect(data_dir) as db, db:
            db.executemany("INSERT INTO divisions(id,number,at,bill,description,result,yeas,nays,paired) "
                           "VALUES (:id,:number,:at,:bill,:description,:result,:yeas,:nays,:paired) "
                           "ON CONFLICT(id) DO UPDATE SET number=excluded.number,at=excluded.at,bill=excluded.bill,"
                           "description=excluded.description,result=excluded.result,yeas=excluded.yeas,nays=excluded.nays,paired=excluded.paired",
                           parse_divisions(body))
            pending = db.execute("SELECT id,number FROM divisions WHERE ballots_loaded=0 ORDER BY at,number").fetchall()
        for division, number in pending:
            sleep(1.0)
            try:
                body = fetch(VOTES + f"45/1/{number}/xml")
                store_raw(data_dir, "ballots", body, now, key="ballots/" + division)
                rows = parse_ballots(body)
                with connect(data_dir) as db, db:
                    db.execute("BEGIN IMMEDIATE")
                    db.execute("DELETE FROM ballots WHERE division=?", (division,))
                    db.executemany("INSERT INTO ballots VALUES (?,?,?,?)", [(division, r["person_id"], r["party"], r["vote"]) for r in rows])
                    db.execute("UPDATE divisions SET ballots_loaded=1 WHERE id=?", (division,))
            except Exception as exc:
                error = str(exc) or type(exc).__name__
        return _status(data_dir, "votes", now, error)
    except Exception as exc:
        return _status(data_dir, "votes", now, str(exc) or type(exc).__name__)


def main(argv=None):
    parser = argparse.ArgumentParser(description="Poll Parliament watch records")
    parser.add_argument("--data", default=DEFAULT_DATA)
    parser.add_argument("--sources", default="hansard,evidence,votes,bills")
    parser.add_argument("--max-docs", type=int)
    args = parser.parse_args(argv)
    sources = args.sources.split(",")
    if any(source not in ("hansard", "evidence", "votes", "bills", "parlvu", "opinion") for source in sources):
        parser.error("unknown source")
    now, outcomes = datetime.now(timezone.utc), []
    for source in sources:
        if source == "bills":
            ok = ingest_source(args.data, source, fetch=fetch, now=now)
        elif source == "parlvu":
            from watch.parlvu import poll_parlvu
            ok = poll_parlvu(args.data, fetch, sleep, now)
        elif source == "opinion":
            from watch.opinion.sources import poll_opinion
            ok = poll_opinion(args.data, fetch, now)
        elif source == "votes":
            ok = poll_votes(args.data, fetch, sleep, now)
        else:
            ok = {"hansard": poll_hansard, "evidence": poll_evidence}[source](args.data, fetch, sleep, now, max_docs=args.max_docs)
        outcomes.append(ok)
        sys.stderr.write("%s %s\n" % (source, "ok" if ok else "failed"))
    if "votes" in sources:
        # A recorded result on a followed bill is the second bill_vote alert.
        from watch.live import alert_tick
        alert_tick(args.data, datetime.now(timezone.utc))
    return 0 if all(outcomes) else 1


if __name__ == "__main__":
    sys.exit(main())
