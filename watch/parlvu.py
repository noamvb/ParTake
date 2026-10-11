"""ParlVU event discovery and archived captions with injectable polling."""

from datetime import date, datetime, timedelta, timezone
import json
import re
from zoneinfo import ZoneInfo

from watch.ingest import store_raw
from watch.store import connect, iso, set_meta


BASE = "https://parlvu.parl.gc.ca"
OTTAWA = ZoneInfo("America/Toronto")


def ottawa_utc(value):
    if value is None:
        return None
    at = datetime.fromisoformat(value)
    if at.tzinfo is None:
        at = at.replace(tzinfo=OTTAWA)
    precision = "milliseconds" if "." in value else "seconds"
    return at.astimezone(timezone.utc).isoformat(timespec=precision).replace("+00:00", "Z")


def parse_listing(body):
    return [row for week in json.loads(body)["Weeks"] for row in week["ContentEntityDatas"]]


def parse_upcoming(body):
    return [row for group in json.loads(body)["ContentEntityDatas"] for row in group]


def event_row(row, now):
    house = re.fullmatch(r"HoC Sitting No\. (\d+)", row["Title"])
    committee = re.fullmatch(r"([A-Z]{3,5}) Meeting No\. (\d+)", row["Title"])
    if house:
        kind, acronym, number = "house", None, int(house[1])
        document, title = f"hansard/45-1/{number}", f"House of Commons, sitting {number}"
    elif committee:
        kind, acronym, number = "committee", committee[1], int(committee[2])
        document, title = f"evidence/45-1/{acronym}/{number}", f"{acronym}, meeting {number}"
    else:
        return None
    return dict(id=str(row["Id"]), title=title, kind=kind, committee=acronym, number=number,
                document=document, scheduled_start=ottawa_utc(row["ScheduledStart"]),
                actual_start=ottawa_utc(row.get("ActualStart")), actual_end=ottawa_utc(row.get("ActualEnd")),
                status=row["EntityStatus"], has_archive=int(bool(row.get("HasArchiveStream"))),
                recording_start=None, preroll_s=None, stream_url=None, captions="none", updated_at=iso(now))


def _embedded(html, marker, nullable=False):
    if html.count(marker) != 1:
        raise ValueError(marker.strip() + " marker is missing or ambiguous")
    start = html.index(marker) + len(marker)
    while start < len(html) and html[start].isspace():
        start += 1
    if nullable and html.startswith("null", start):
        return None
    if start >= len(html) or html[start] not in "[{":
        raise ValueError(marker.strip() + " value is missing")
    opener = html[start]
    closer = "]" if opener == "[" else "}"
    depth, quoted, escaped = 0, False, False
    for end in range(start, len(html)):
        char = html[end]
        if quoted:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                quoted = False
            continue
        if char == '"':
            quoted = True
        elif char == opener:
            depth += 1
        elif char == closer:
            depth -= 1
            if depth == 0:
                try:
                    return json.loads(html[start:end + 1])
                except ValueError as exc:
                    raise ValueError(marker.strip() + " value does not decode") from exc
    raise ValueError(marker.strip() + " value is incomplete")


def parse_event_page(html):
    if isinstance(html, bytes):
        html = html.decode("utf-8-sig")
    streams = _embedded(html, "var availableStreams = ")
    info = _embedded(html, "\tEventInfo:")
    captions = _embedded(html, "\tccItems:", nullable=True)
    if not isinstance(streams, list) or not isinstance(info, dict):
        raise ValueError("invalid event values")
    if captions is not None and not isinstance(captions, dict):
        raise ValueError("ccItems must be an object")
    try:
        recording_start = iso(datetime.fromisoformat(ottawa_utc(info["timeTags"]["STARTTIME"]["timestamp"])))
        stream = None
        for entry in streams:
            if not isinstance(entry, dict):
                raise ValueError("stream must be an object")
            if entry.get("Lang") == "en" and entry.get("AudioOnly") is False and entry.get("Tag", "").endswith(" SD"):
                stream = entry
                break
        stream_url = stream["Url"] if stream is not None else None
        preroll_s = float(stream["PreRoll"]) if stream is not None else None
        if stream is not None and not isinstance(stream_url, str):
            raise ValueError("stream URL must be a string")
        if captions is not None:
            for lang in ("en", "fr"):
                if lang in captions and not isinstance(captions[lang], list):
                    raise ValueError("ccItems language must be a list")
    except (KeyError, TypeError, AttributeError, ValueError) as exc:
        raise ValueError("invalid event fields") from exc
    return dict(recording_start=recording_start, preroll_s=preroll_s, stream_url=stream_url, captions=captions)


def _caption_time(value):
    at = ottawa_utc(value)
    return at if "." in at else at[:-1] + ".000Z"


def caption_rows(event_id, page, lang="en"):
    result = []
    for item in (page["captions"] or {}).get(lang, []):
        text = item["Content"].strip()
        if text:
            result.append(dict(event=event_id, lang=lang, source="archive", seq=len(result),
                               begin=_caption_time(item["Begin"]), end=_caption_time(item["End"]), text=text))
    return result


def _status(data_dir, now, error=None):
    with connect(data_dir) as db, db:
        set_meta(db, "source:parlvu", json.dumps(dict(at=iso(now), ok=error is None, error=error)))
    return error is None


def _save_events(data_dir, rows, now, through=None):
    events = [event for row in rows if (event := event_row(row, now)) is not None]
    with connect(data_dir) as db, db:
        db.executemany("INSERT INTO events(id,title,kind,committee,number,document,scheduled_start,actual_start,actual_end,"
                       "status,has_archive,recording_start,preroll_s,stream_url,captions,updated_at) "
                       "VALUES (:id,:title,:kind,:committee,:number,:document,:scheduled_start,:actual_start,:actual_end,"
                       ":status,:has_archive,:recording_start,:preroll_s,:stream_url,:captions,:updated_at) "
                       "ON CONFLICT(id) DO UPDATE SET title=excluded.title,kind=excluded.kind,committee=excluded.committee,"
                       "number=excluded.number,document=excluded.document,scheduled_start=excluded.scheduled_start,"
                       "actual_start=excluded.actual_start,actual_end=excluded.actual_end,status=excluded.status,"
                       "has_archive=excluded.has_archive,updated_at=excluded.updated_at", events)
        if through is not None:
            set_meta(db, "parlvu:through", through.isoformat())


def poll_parlvu(data_dir, fetch, sleep, now, max_days=60, max_pages=5):
    fetched, error = False, None

    def get(url, source, key):
        nonlocal fetched
        if fetched:
            sleep(1.0)
        fetched = True
        body = fetch(url)
        store_raw(data_dir, source, body, now, key=key)
        return body

    def listing(day, advance=False):
        stamp = day.strftime("%Y%m%d")
        url = BASE + (f"/Harmony/en/api/Data/GetListViewData?categoryId=-1&fromDate={stamp}&endDate={stamp}"
                      "&searchTime=&searchForward=true&order=asc")
        body = get(url, "parlvu", "parlvu/listing/" + stamp)
        _save_events(data_dir, parse_listing(body), now, day if advance else None)

    try:
        today = now.astimezone(OTTAWA).date()
        with connect(data_dir) as db:
            cursor = db.execute("SELECT value FROM meta WHERE key='parlvu:through'").fetchone()
        day = date.fromisoformat(cursor[0]) + timedelta(days=1) if cursor else date(2025, 5, 26)
        count = 0
        while day <= today and count < max_days:
            listing(day, advance=day < today)
            day += timedelta(days=1)
            count += 1
        for day in (today - timedelta(days=1), today):
            listing(day)
        body = get(BASE + "/Harmony/en/api/Data/GetUpcomingEvents?lastModified=", "parlvu", "parlvu/upcoming")
        _save_events(data_dir, parse_upcoming(body), now)
        with connect(data_dir) as db:
            pending = db.execute("SELECT id FROM events WHERE status=-1 AND captions IN ('none','live') "
                                 "AND coalesce((SELECT CAST(value AS INTEGER) FROM meta WHERE key='parlvu:nocc:' || events.id),0)<3 "
                                 "ORDER BY scheduled_start DESC LIMIT ?", (max_pages,)).fetchall()
        for event in pending:
            event_id = event["id"]
            try:
                body = get(BASE + "/Harmony/en/PowerBrowser/PowerBrowserV2/-1/-1/" + event_id,
                           "parlvu_pages", "parlvu/event/" + event_id)
                page = parse_event_page(body)
                rows = caption_rows(event_id, page)
                with connect(data_dir) as db, db:
                    db.execute("BEGIN IMMEDIATE")
                    db.execute("UPDATE events SET recording_start=?,preroll_s=?,stream_url=? WHERE id=?",
                               (page["recording_start"], page["preroll_s"], page["stream_url"], event_id))
                    if rows:
                        db.execute("DELETE FROM captions WHERE event=? AND lang='en' AND source='archive'", (event_id,))
                        db.executemany("INSERT INTO captions(event,lang,source,seq,begin,end,text) "
                                       "VALUES (:event,:lang,:source,:seq,:begin,:end,:text)", rows)
                        db.execute("UPDATE events SET captions='archive' WHERE id=?", (event_id,))
                    else:
                        key = "parlvu:nocc:" + event_id
                        previous = db.execute("SELECT value FROM meta WHERE key=?", (key,)).fetchone()
                        set_meta(db, key, str(int(previous[0]) + 1 if previous else 1))
            except Exception as exc:
                error = str(exc) or type(exc).__name__
        return _status(data_dir, now, error)
    except Exception as exc:
        return _status(data_dir, now, str(exc) or type(exc).__name__)
