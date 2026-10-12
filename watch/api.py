"""Authenticated follow writes and public Parliament watch lookups."""

import argparse
from datetime import datetime, timezone
import hmac
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import re
import secrets
import sys
import unicodedata
from urllib.parse import parse_qs, urlsplit

from watch import digest, embed
from watch.feed import feed, _speaker
from watch.opinion.results import ELECTION, results_from_db
from watch.opinion.swing import PARTIES, shares

from watch.store import (DEFAULT_DATA, StaleVersion, connect, follow_id, import_follows,
                         iso, list_follows, replace_follows)


MAX_BODY = 1024 * 1024


def normalized(value):
    return "".join(c for c in unicodedata.normalize("NFKD", value.casefold()) if not unicodedata.combining(c))


def number_key(value):
    return "".join(c for c in value.casefold() if c.isalnum())


def members(db, query):
    q = normalized(query)
    roles = {}
    for row in db.execute("SELECT * FROM ministries ORDER BY precedence"):
        roles.setdefault(row["person_id"], []).append(row["title"])
    results = []
    for row in db.execute("SELECT * FROM members"):
        name, riding = normalized(row["name"]), normalized(row["riding"])
        if q not in name and q not in riding:
            continue
        last, first = normalized(row["last_name"]), normalized(row["first_name"])
        rank = 0 if last.startswith(q) else 1 if name.startswith(q) else 2
        item = {k: row[k] for k in ("person_id", "name", "party", "riding", "province")}
        item["role"] = "; ".join(roles[row["person_id"]]) if row["person_id"] in roles else None
        results.append(((rank, last, first), item))
    return [item for _key, item in sorted(results, key=lambda r: r[0])[:20]]


def bills(db, query):
    q, number = normalized(query), number_key(query)
    results = []
    for row in db.execute("SELECT * FROM bills"):
        exact = bool(number) and number_key(row["number"]) == number
        if exact or q in normalized(row["title"]):
            results.append(((0 if exact else 1, row["number"]), dict(row)))
    return [item for _key, item in sorted(results, key=lambda r: r[0])[:20]]


POLL_REGIONS = ("CAN", "ATL", "QC", "ON", "PR", "AB", "BC", "TERR")
OPINION_URL = "https://338canada.com/polls.htm"
WIKI_URL = "https://en.wikipedia.org/wiki/Opinion_polling_for_the_46th_Canadian_federal_election"


def _meta(db, key):
    row = db.execute("SELECT value FROM meta WHERE key=?", (key,)).fetchone()
    return row[0] if row else None


def _share(value):
    value = round(value, 1)
    return int(value) if value.is_integer() else value


def polls_list(db, region, limit, before):
    if region not in POLL_REGIONS:
        raise ValueError("unknown region")
    if not 1 <= limit <= 200:
        raise ValueError("limit must be between 1 and 200")
    where, params = "region=?", [region]
    if before is not None:
        end, sep, poll_id = before.partition("|")
        if not sep or not end or not poll_id:
            raise ValueError("invalid cursor")
        where += " AND (end_date < ? OR (end_date = ? AND id < ?))"
        params += [end, end, poll_id]
    rows = db.execute("SELECT * FROM opinion_polls WHERE " + where + " ORDER BY end_date DESC, id DESC LIMIT ?",
                      (*params, limit + 1)).fetchall()
    page = rows[:limit]
    polls = [dict(id=row["id"], firm=row["firm"], end_date=row["end_date"], sample=row["sample"],
                  rolling=row["rolling"], link=row["link"], region=row["region"],
                  shares={party: _share(row[party.lower()]) for party in ("LPC", "CPC", "NDP", "GPC", "BQ", "OTH")})
             for row in page]
    next_cursor = "%s|%s" % (page[-1]["end_date"], page[-1]["id"]) if len(rows) > limit else None
    return {"polls": polls, "next": next_cursor,
            "source": {"name": "338Canada", "url": OPINION_URL, "fetched_at": _meta(db, "opinion:fetched_at")}}


def polls_leaders(db):
    best = [dict(firm=row["firm"], end_date=row["end_date"],
                 shares={name: _share(value) for name, value in json.loads(row["body"]).items()})
            for row in db.execute("SELECT * FROM leader_polls WHERE kind='best_pm' "
                                  "ORDER BY end_date DESC, firm LIMIT 100")]
    approval = [dict(firm=row["firm"], end_date=row["end_date"],
                     **{k: _share(v) for k, v in json.loads(row["body"]).items()})
                for row in db.execute("SELECT * FROM leader_polls WHERE kind='approval' "
                                      "ORDER BY end_date DESC, firm LIMIT 100")]
    return {"best_pm": best, "approval": approval,
            "source": {"name": "Wikipedia", "url": WIKI_URL, "licence": "CC BY-SA 4.0",
                       "fetched_at": _meta(db, "opinion_wiki:fetched_at")}}


SEATS_TOTAL, MAJORITY_LINE = 343, 172
MP_PARTIES = {"Liberal": "LPC", "Conservative": "CPC", "Bloc Québécois": "BQ", "NDP": "NDP", "Green Party": "GPC"}
MP_PROVINCES = {"Newfoundland and Labrador": "NL", "Prince Edward Island": "PE", "Nova Scotia": "NS",
                "New Brunswick": "NB", "Quebec": "QC", "Ontario": "ON", "Manitoba": "MB", "Saskatchewan": "SK",
                "Alberta": "AB", "British Columbia": "BC", "Yukon": "YT", "Northwest Territories": "NT", "Nunavut": "NU"}


def _name_key(value):
    return " ".join(re.sub(r"[\W_]+", " ", normalized(value or "")).split())


def _rounded(shares):
    return {party: round(value, 1) for party, value in shares.items()}


def _model_party(party):
    return party if party in PARTIES else "OTH"


def _link_members(db):
    """riding id -> members row of the sitting MP: same riding name in the province, else the 2025 winner's family name."""
    winners = {row["riding"]: row for row in db.execute("SELECT * FROM riding_winners WHERE election=?", (ELECTION,))}
    ridings = [dict(id=row["id"], province=row["province"], name=_name_key(row["name_en"]),
                    family=_name_key(winners[row["id"]]["family"]) if row["id"] in winners else None,
                    first=_name_key(winners[row["id"]]["first"]) if row["id"] in winners else None)
               for row in db.execute("SELECT * FROM ridings ORDER BY id")]
    linked, pending = {}, []
    for member in db.execute("SELECT * FROM members ORDER BY person_id"):
        province = MP_PROVINCES.get(member["province"])
        named = [r["id"] for r in ridings if r["province"] == province and r["name"] == _name_key(member["riding"])]
        if len(named) == 1 and named[0] not in linked:
            linked[named[0]] = member
        else:
            pending.append(member)
    for member in pending:
        province, last = MP_PROVINCES.get(member["province"]), _name_key(member["last_name"])
        family = [r for r in ridings if r["province"] == province and r["id"] not in linked and r["family"] == last]
        if len(family) > 1:
            family = [r for r in family if r["first"] == _name_key(member["first_name"])]
        if len(family) == 1:
            linked[family[0]["id"]] = member
    return linked


def _status(holder, projection):
    if projection is None:
        return None
    if projection["winner"] != holder:
        return "projected_loss"
    margin = projection["margin"]
    return "safe" if margin > 10 else "likely" if margin > 5 else "at_risk"


def polls_ridings(db, mp=None):
    """All ridings by name, or only the riding of the MP with PersonId mp; None when that MP holds none."""
    linked = _link_members(db)
    won = {row["riding"]: _model_party(row["party"]) for row in db.execute(
        "SELECT riding, party FROM riding_results WHERE election=? AND elected=1", (ELECTION,))}
    latest = {row["riding"]: row for row in db.execute(
        "SELECT * FROM riding_projections rp WHERE date = (SELECT max(date) FROM riding_projections WHERE riding = rp.riding)")}
    items = []
    for riding in db.execute("SELECT * FROM ridings ORDER BY name_en"):
        member = linked.get(riding["id"])
        party = MP_PARTIES.get(member["party"], "OTH") if member else None
        projection = latest.get(riding["id"])
        items.append(dict(id=riding["id"], name=riding["name_en"].replace("--", "\u2014"), province=riding["province"], region=riding["region"],
                          mp=None if member is None else dict(person_id=member["person_id"], name=member["name"],
                                                               party=party),
                          won_2025=won.get(riding["id"]), projected=projection["winner"] if projection else None,
                          win_prob=None, status=_status(party or won.get(riding["id"]), projection)))
    if mp is not None:
        items = [item for item in items if item["mp"] and item["mp"]["person_id"] == mp]
        return {"ridings": items} if items else None
    return {"ridings": items}


def polls_riding(db, riding_id):
    listed = polls_ridings(db)["ridings"]
    item = next((item for item in listed if item["id"] == riding_id), None)
    if item is None:
        return None
    votes = results_from_db(db).get(riding_id)
    history = db.execute("SELECT date, shares FROM riding_projections WHERE riding=? ORDER BY date", (riding_id,)).fetchall()
    item.update(results_2025=_rounded(shares(votes["votes"])) if votes else None,
                projection=_rounded(json.loads(history[-1]["shares"])) if history else None,
                history=[dict(date=row["date"], shares=_rounded(json.loads(row["shares"]))) for row in history])
    return item


def polls_summary(db, history=True):
    rows = db.execute("SELECT date, body FROM projections ORDER BY date").fetchall()
    if not rows:
        return None
    entries = [(row["date"], json.loads(row["body"])) for row in rows]
    as_of, body = entries[-1]
    return dict(as_of=as_of, polls_used=body["polls_used"],
                average={region: _rounded(values) for region, values in body["average"].items()},
                seats={party: dict(median=count, low=count, high=count) for party, count in body["seats"]["CAN"].items()},
                majority=None, minority=None, seats_total=SEATS_TOTAL, majority_line=MAJORITY_LINE,
                comparison=None, note=None,
                history=[dict(date=day, average=_rounded(past["average"]["CAN"]), seats=past["seats"]["CAN"])
                         for day, past in entries] if history else [])


def _fresh(at, now):
    return 0 <= (now - datetime.fromisoformat(at)).total_seconds() <= 180


def live(db, now):
    rows = []
    for event in db.execute('SELECT * FROM events'):
        ends = [row[0] for row in db.execute("SELECT end FROM captions WHERE event=? AND source='live'", (event['id'],))]
        if not ends:
            continue
        newest = max(ends, key=datetime.fromisoformat)
        if not _fresh(newest, now):
            continue
        paragraphs = db.execute("SELECT * FROM paragraphs WHERE event_id=? AND source='captions' ORDER BY position DESC,seq DESC", (event['id'],)).fetchall()
        paragraph = max(paragraphs, key=lambda row: datetime.fromisoformat(row['at'])) if paragraphs else None
        rows.append(dict(event=event['id'], title=event['title'], kind=event['kind'],
                         speaker=_speaker(db, paragraph) if paragraph else None,
                         last_line_at=newest, business=None))
    return sorted(rows, key=lambda row: datetime.fromisoformat(row['last_line_at']), reverse=True)


def _event_health(db, now):
    today = now.astimezone(digest.OTTAWA).date()
    sitting = False
    recorders = []
    for event in db.execute('SELECT * FROM events ORDER BY id'):
        if event['kind'] == 'house' and datetime.fromisoformat(event['scheduled_start']).astimezone(digest.OTTAWA).date() == today:
            sitting = True
        meta = db.execute('SELECT value FROM meta WHERE key=?', ('recorder:' + event['id'],)).fetchone()
        if meta is None or not _fresh(json.loads(meta[0])['at'], now):
            continue
        begins = [row[0] for row in db.execute("SELECT begin FROM captions WHERE event=? AND source='live'", (event['id'],))]
        recorders.append(dict(event=event['id'], title=event['title'],
                              since=min(begins, key=datetime.fromisoformat) if begins else None, lines=len(begins)))
    return sitting, recorders


def make_server(data_dir, host, port, clock=None, new_id=None, ollama=None):
    ollama = ollama or embed.URL
    data_dir = Path(data_dir).expanduser()
    with connect(data_dir):
        pass
    token_path = data_dir / "token"
    try:
        fd = os.open(token_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        pass
    else:
        with os.fdopen(fd, "w") as token_file:
            token_file.write(secrets.token_urlsafe(24))
    token = token_path.read_text().strip()
    clock = clock or (lambda: datetime.now(timezone.utc))
    new_id = new_id or follow_id

    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, _format, *_args):
            pass

        def _send(self, status, value):
            body = json.dumps(value, ensure_ascii=False).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            if self.command != "HEAD":
                self.wfile.write(body)
            sys.stderr.write("%s %s %d\n" % (self.command, urlsplit(self.path).path, status))

        def _error(self, status, message):
            self._send(status, {"error": message})

        def _body(self):
            try:
                size = int(self.headers.get("Content-Length", "0"))
            except ValueError:
                raise ValueError("invalid content length")
            if size < 0:
                raise ValueError("invalid content length")
            if size > MAX_BODY:
                self.close_connection = True
                raise OverflowError("body too large")
            return json.loads(self.rfile.read(size))

        def _handle(self):
            parts = urlsplit(self.path)
            path = parts.path
            writing = self.command in ("PUT", "POST", "DELETE")
            if writing and not hmac.compare_digest(
                    self.headers.get("Authorization", "").encode(), ("Bearer " + token).encode()):
                self.close_connection = True
                self._error(401, "unauthorized")
                return
            try:
                if self.command in ("GET", "HEAD"):
                    with connect(data_dir) as db:
                        if path == "/api/follows":
                            self._send(200, list_follows(db))
                        elif path == "/api/feed":
                            query = parse_qs(parts.query, keep_blank_values=True)
                            self._send(200, feed(db, follows=query.get("follow"),
                                                 kind=query.get("kind", [None])[0],
                                                 limit=int(query.get("limit", ["50"])[0]),
                                                 before=query.get("before", [None])[0]))
                        elif path == "/api/digests":
                            query = parse_qs(parts.query, keep_blank_values=True)
                            limit = int(query.get("limit", ["20"])[0])
                            if not 1 <= limit <= 100:
                                raise ValueError("limit must be between 1 and 100")
                            rows = []
                            for row in db.execute('SELECT * FROM digests ORDER BY created_at DESC,id DESC LIMIT ?', (limit,)):
                                item = {k: row[k] for k in ('id', 'date', 'kind', 'created_at', 'replaces')}
                                item['items'] = digest.item_count(json.loads(row['body']))
                                rows.append(item)
                            self._send(200, rows)
                        elif path.startswith("/api/digests/"):
                            row = db.execute('SELECT body FROM digests WHERE id=?', (path[len('/api/digests/'):],)).fetchone()
                            if row:
                                self._send(200, json.loads(row[0]))
                            else:
                                self._error(404, "not found")
                        elif path == "/api/live":
                            self._send(200, live(db, clock()))
                        elif path == "/api/polls/list":
                            query = parse_qs(parts.query, keep_blank_values=True)
                            self._send(200, polls_list(db, query.get("region", ["CAN"])[0],
                                                       int(query.get("limit", ["50"])[0]),
                                                       query.get("before", [None])[0]))
                        elif path == "/api/polls/leaders":
                            self._send(200, polls_leaders(db))
                        elif path == "/api/polls/summary":
                            query = parse_qs(parts.query, keep_blank_values=True)
                            summary = polls_summary(db, history=query.get("history", ["1"])[0] != "0")
                            if summary is None:
                                self._error(404, "no projection yet")
                            else:
                                self._send(200, summary)
                        elif path == "/api/polls/ridings":
                            query = parse_qs(parts.query, keep_blank_values=True)
                            listed = polls_ridings(db, mp=query.get("mp", [None])[0])
                            if listed is None:
                                self._error(404, "not found")
                            else:
                                self._send(200, listed)
                        elif path.startswith("/api/polls/ridings/"):
                            riding = polls_riding(db, path[len("/api/polls/ridings/"):])
                            if riding is None:
                                self._error(404, "not found")
                            else:
                                self._send(200, riding)
                        elif path == "/api/health":
                            sources = {row["key"][7:]: json.loads(row["value"]) for row in db.execute(
                                "SELECT key,value FROM meta WHERE key LIKE 'source:%'")}
                            backfill = db.execute("SELECT value FROM meta WHERE key='backfill'").fetchone()
                            now = clock()
                            sitting, recorders = _event_health(db, now)
                            self._send(200, {"ok": True, "version": "0.1.0", "now": iso(now),
                                             "sitting_today": sitting, "recorders": recorders,
                                             "embed": {"model": embed.MODEL, "loaded": embed.loaded(ollama)},
                                             "backfill": json.loads(backfill[0]) if backfill else None, "sources": sources})
                        elif path in ("/api/members", "/api/bills"):
                            query = parse_qs(parts.query).get("q", [""])[0].strip()
                            if not query:
                                raise ValueError("q required")
                            lookup = members if path == "/api/members" else bills
                            self._send(200, lookup(db, query))
                        else:
                            self._error(404, "not found")
                elif (self.command, path) in (("PUT", "/api/follows"), ("POST", "/api/follows/import")):
                    body = self._body()
                    writer = replace_follows if self.command == "PUT" else import_follows
                    self._send(200, writer(data_dir, body, clock, new_id))
                else:
                    self._error(404, "not found")
            except OverflowError:
                self._error(413, "body too large")
            except StaleVersion as exc:
                self._send(409, exc.current)
            except (ValueError, UnicodeError, TypeError) as exc:
                self._error(400, str(exc))
            except Exception:
                self._error(500, "internal server error")

        do_GET = do_HEAD = do_PUT = do_POST = do_DELETE = _handle

        def __getattr__(self, name):
            if name.startswith("do_"):
                return lambda: self._error(404, "not found")
            raise AttributeError(name)

    server = ThreadingHTTPServer((host, port), Handler)
    server.daemon_threads = True
    return server


def main(argv=None):
    parser = argparse.ArgumentParser(description="Serve Parliament watch")
    parser.add_argument("--data", default=DEFAULT_DATA)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8798)
    args = parser.parse_args(argv)
    server = make_server(args.data, args.host, args.port)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
