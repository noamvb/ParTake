"""Opinion polls from 338Canada and leader/approval polls from Wikipedia, plus the daily poll job."""

from datetime import datetime
from html.parser import HTMLParser
import json
import re
import sys

from watch.ingest import store_raw
from watch.opinion.comparison import parse_338_seats
from watch.opinion.projection import recompute
from watch.opinion.results import load_results
from watch.store import connect, iso, set_meta


URL_338 = "https://338canada.com/polls.htm"
URL_338_FRONT = "https://338canada.com/federal.htm"
WIKI_API = "https://en.wikipedia.org/w/api.php?action=parse&page=Opinion_polling_for_the_46th_Canadian_federal_election"
WIKI_PAGE = "https://en.wikipedia.org/wiki/Opinion_polling_for_the_46th_Canadian_federal_election"
# Section numbers used when the sections list cannot be read.
WIKI_SECTIONS = {"best_pm": (14, "Leadership polls"), "approval": (19, "Government approval polls")}
REGIONS = {"National": "CAN", "ATL": "ATL", "QC": "QC", "ON": "ON", "PR": "PR", "AB": "AB", "BC": "BC"}
PARTIES = ("LPC", "CPC", "NDP", "GPC", "BQ")
LEADER = re.compile(r"^[A-Z]+ \+(\d+)$")
ROLLING = re.compile(r"\((\d+)/(\d+)\)")
NOT_LEADERS = {"Polling firm", "Last date of polling", "Link", "Margin of error", "Sample size",
               "Polling method", "Lead"}  # plus any header starting with "Unsure"
# first_seen is set on insert only: the day a poll first appeared in the table.
UPSERT_POLL = ("INSERT INTO opinion_polls (id,region,firm,end_date,sample,rolling,link,lpc,cpc,ndp,gpc,bq,oth,"
               "fetched_at,first_seen) VALUES (:id,:region,:firm,:end_date,:sample,:rolling,:link,"
               ":lpc,:cpc,:ndp,:gpc,:bq,:oth,:fetched_at,:first_seen) "
               "ON CONFLICT(id, region) DO UPDATE SET firm=excluded.firm, end_date=excluded.end_date, "
               "sample=excluded.sample, rolling=excluded.rolling, link=excluded.link, lpc=excluded.lpc, "
               "cpc=excluded.cpc, ndp=excluded.ndp, gpc=excluded.gpc, bq=excluded.bq, oth=excluded.oth, "
               "fetched_at=excluded.fetched_at")


def _slug(text):
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")


def _sample(text):
    text = text.replace(",", "").strip()
    return int(text) if text.isdigit() else None


def _rolling(markup):
    if not markup:
        return 1.0
    match = ROLLING.search(markup)
    if match is None or int(match.group(2)) == 0:
        raise ValueError("unreadable isRolling")
    return int(match.group(1)) / int(match.group(2))


def _shares(cells):
    # polls2.htm adds a PPC cell after the five parties; polls.htm has none.
    if len(cells) not in (5, 6):
        raise ValueError("expected 5 or 6 cells")
    names = PARTIES if len(cells) == 5 else PARTIES + ("PPC",)
    values = [int(cell["label"]) if cell["label"] else 0 for cell in cells]
    shares = dict(zip(names, values))
    shares["OTH"] = max(0, 100 - sum(values))
    return shares


def _leader_ok(leader, shares):
    match = LEADER.match(leader or "")
    if match is None:
        return True
    top, second = sorted((value for party, value in shares.items() if party != "OTH"), reverse=True)[:2]
    return int(match.group(1)) == top - second


def _stored(shares):
    # The table has no PPC column: PPC is Others in the model, so it is stored as Others.
    stored = {party.lower(): value for party, value in shares.items() if party != "PPC"}
    stored["oth"] += shares.get("PPC", 0)
    return stored


def parse_338(html):
    text = html.decode("utf-8")
    marker = "window.demopoll_TABLE_DATA = "
    start = text.index(marker) + len(marker)
    data, _end = json.JSONDecoder().raw_decode(text, start)
    polls, skipped = [], 0
    for key, region in REGIONS.items():
        used = {}
        for row in data["demos"][key]["rows"]:
            if row["generalelx"]:
                continue
            try:
                shares = _shares(row["cells"])
                rolling = _rolling(row["isRolling"])
                if not _leader_ok(row["leader"], shares):
                    raise ValueError("leader margin mismatch")
            except (ValueError, TypeError, KeyError):
                skipped += 1
                continue
            base = "338:%s:%s" % (row["date"], _slug(row["firm"]))
            poll_id, n = base, 1
            while poll_id in used:
                n += 1
                poll_id = "%s-%d" % (base, n)
            used[poll_id] = True
            polls.append(dict(id=poll_id, firm=row["firm"], end_date=row["date"], sample=_sample(row["sample"]),
                              rolling=rolling, link=row["poll_link"], region=region, shares=shares))
    return {"polls": polls, "skipped": skipped}


class _Tables(HTMLParser):
    """Every wikitable as rows of (is_header, text) cells; reference marks like [1] are dropped."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.tables = []
        self._table = self._row = self._cell = None
        self._header = False

    def handle_starttag(self, tag, attrs):
        if tag == "table":
            classes = (dict(attrs).get("class") or "").split()
            self._table = [] if "wikitable" in classes else None
            if self._table is not None:
                self.tables.append(self._table)
        elif tag == "tr" and self._table is not None:
            self._row = []
            self._table.append(self._row)
        elif tag in ("td", "th") and self._row is not None:
            self._cell = []
            self._header = tag == "th"

    def handle_endtag(self, tag):
        if tag in ("td", "th") and self._cell is not None:
            text = re.sub(r"\[[^\]]*\]", "", "".join(self._cell))
            self._row.append((self._header, " ".join(text.split())))
            self._cell = None
        elif tag == "tr":
            self._row = None
        elif tag == "table":
            self._table = None

    def handle_data(self, data):
        if self._cell is not None:
            self._cell.append(data)


def _tables(payload):
    parser = _Tables()
    parser.feed(json.loads(payload)["parse"]["text"])
    result = []
    for table in parser.tables:
        header_at = next((i for i, row in enumerate(table) if any(h and t for h, t in row)), None)
        if header_at is None:
            continue
        headers = [text for _header, text in table[header_at]]
        body = [[text for _header, text in row] for row in table[header_at + 1:]]
        result.append((headers, body))
    return result


def _cell(row, index):
    return row[index] if index is not None and index < len(row) else ""


def _date(text):
    return datetime.strptime(text, "%B %d, %Y").date().isoformat()


def _number(text):
    text = text.replace("%", "").replace(",", "").strip()
    return float(text) if re.fullmatch(r"\d+(?:\.\d+)?", text) else None


def _sorted_newest(rows):
    rows.sort(key=lambda row: row["firm"])
    rows.sort(key=lambda row: row["end_date"], reverse=True)
    return rows


def parse_best_pm(payload):
    rows = []
    for headers, body in _tables(payload):
        names = [(i, h) for i, h in enumerate(headers) if h and h not in NOT_LEADERS and not h.startswith("Unsure")]
        firm_at = headers.index("Polling firm") if "Polling firm" in headers else 0
        date_at = headers.index("Last date of polling") if "Last date of polling" in headers else 1
        for cells in body:
            try:
                end_date = _date(_cell(cells, date_at))
            except ValueError:
                continue
            shares = {}
            for i, name in names:
                value = _number(_cell(cells, i))
                if value is not None:
                    shares[name] = value
            rows.append(dict(firm=_cell(cells, firm_at), end_date=end_date, shares=shares))
    return _sorted_newest(rows)


def parse_approval(payload):
    rows = []
    for headers, body in _tables(payload):
        lower = [h.lower() for h in headers]
        if "approve" not in lower or "disapprove" not in lower:
            continue
        firm_at = lower.index("polling firm") if "polling firm" in lower else 0
        date_at = next((i for i, h in enumerate(lower) if h.startswith("last date of polling")), 1)
        approve_at, disapprove_at = lower.index("approve"), lower.index("disapprove")
        for cells in body:
            try:
                end_date = _date(_cell(cells, date_at))
                approve = _number(_cell(cells, approve_at))
                disapprove = _number(_cell(cells, disapprove_at))
            except ValueError:
                continue
            if approve is None or disapprove is None:
                continue
            rows.append(dict(firm=_cell(cells, firm_at), end_date=end_date, approve=approve, disapprove=disapprove))
    return _sorted_newest(rows)


def _wiki_url(section):
    return WIKI_API + "&prop=text&section=%d&format=json&formatversion=2" % section


def _wiki_sections(fetch):
    try:
        sections = json.loads(fetch(WIKI_API + "&prop=sections&format=json"))["parse"]["sections"]
        return {s["line"]: int(s["index"]) for s in sections if s.get("index", "").isdigit()}
    except Exception:
        return {}


def _poll_338(data_dir, fetch, now):
    page = fetch(URL_338)
    store_raw(data_dir, "opinion", page, now)
    parsed = parse_338(page)
    fetched_at = iso(now)
    with connect(data_dir) as db, db:
        db.execute("BEGIN IMMEDIATE")
        db.executemany(UPSERT_POLL, [dict(poll, fetched_at=fetched_at, first_seen=fetched_at,
                                          **_stored(poll["shares"])) for poll in parsed["polls"]])
        set_meta(db, "opinion:fetched_at", fetched_at)
        set_meta(db, "opinion:skipped", str(parsed["skipped"]))


def _seats_338(data_dir, fetch, now):
    page = fetch(URL_338_FRONT)
    store_raw(data_dir, "opinion_338seats", page, now)
    result = parse_338_seats(page)
    if result is None:
        raise ValueError("seat projection not found on the federal page")
    with connect(data_dir) as db, db:
        set_meta(db, "opinion:338_seats", json.dumps(result))


def _poll_wiki(data_dir, fetch, now):
    sections = _wiki_sections(fetch)
    errors = []
    for kind, parse in (("best_pm", parse_best_pm), ("approval", parse_approval)):
        default, line = WIKI_SECTIONS[kind]
        try:
            body = fetch(_wiki_url(sections.get(line, default)))
            store_raw(data_dir, "opinion_wiki", body, now, key="opinion_wiki/" + kind)
            rows = parse(body)
            if not rows:
                raise ValueError("no %s rows parsed" % kind)
            with connect(data_dir) as db, db:
                db.execute("BEGIN IMMEDIATE")
                db.execute("DELETE FROM leader_polls WHERE kind=?", (kind,))
                db.executemany("INSERT INTO leader_polls VALUES (?,?,?,?)",
                               [(kind, row["firm"], row["end_date"], json.dumps(_body(kind, row))) for row in rows])
                set_meta(db, "opinion_wiki:fetched_at", iso(now))
        except Exception as exc:
            errors.append("wikipedia %s: %s" % (kind, str(exc) or type(exc).__name__))
    return errors


def _body(kind, row):
    return row["shares"] if kind == "best_pm" else {"approve": row["approve"], "disapprove": row["disapprove"]}


def poll_opinion(data_dir, fetch, now):
    load_results(data_dir, fetch, now)
    errors = []
    polls_ok = False
    try:
        _poll_338(data_dir, fetch, now)
        polls_ok = True
    except Exception as exc:
        errors.append("338Canada: " + (str(exc) or type(exc).__name__))
    try:
        _seats_338(data_dir, fetch, now)
    except Exception as exc:
        # Comparison only: a failure is logged and never fails the poll run.
        sys.stderr.write("338Canada seats: %s\n" % (str(exc) or type(exc).__name__))
    errors.extend(_poll_wiki(data_dir, fetch, now))
    if polls_ok:
        try:
            recompute(data_dir, now)
        except Exception as exc:
            errors.append("projection: " + (str(exc) or type(exc).__name__))
    error = "; ".join(errors) or None
    with connect(data_dir) as db, db:
        set_meta(db, "source:opinion", json.dumps(dict(at=iso(now), ok=error is None, error=error)))
    return error is None
