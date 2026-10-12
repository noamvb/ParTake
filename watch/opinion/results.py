"""Elections Canada 2025 riding results: polling-division CSVs in one zip -> riding and party tables."""

import argparse
import csv
from datetime import datetime, timezone
import io
import json
import sys
import zipfile

from watch.ingest import fetch, store_raw
from watch.store import DEFAULT_DATA, connect, iso, set_meta


URL = "https://elections.ca/res/rep/off/ovrGE45/62/data_donnees/pollresults_resultatsbureauCanada.zip"
ELECTION = "2025"
PARTIES = {"Liberal": "LPC", "Conservative": "CPC", "NDP-New Democratic Party": "NDP",
           "Green Party": "GPC", "Bloc Québécois": "BQ", "People's Party - PPC": "PPC"}
# Keyed by the first two digits of the district number.
PROVINCES = {"10": ("NL", "ATL"), "11": ("PE", "ATL"), "12": ("NS", "ATL"), "13": ("NB", "ATL"),
             "24": ("QC", "QC"), "35": ("ON", "ON"), "46": ("MB", "PR"), "47": ("SK", "PR"),
             "48": ("AB", "AB"), "59": ("BC", "BC"), "60": ("YT", "TERR"), "61": ("NT", "TERR"),
             "62": ("NU", "TERR")}


def _rows(body):
    with zipfile.ZipFile(io.BytesIO(body)) as archive:
        for name in archive.namelist():
            if not name.endswith(".csv"):
                continue
            rows = csv.reader(io.StringIO(archive.read(name).decode("utf-8-sig")))
            next(rows)
            for row in rows:
                if row:
                    yield row


def parse_results(body):
    ridings, votes, elected = {}, {}, set()
    for row in _rows(body):
        number = row[0].strip()
        if number[:2] not in PROVINCES:
            raise ValueError("unknown district number " + number)
        province, region = PROVINCES[number[:2]]
        ridings.setdefault(number, dict(id=number, name_en=row[1].strip(), name_fr=row[2].strip(),
                                        province=province, region=region))
        key = (number, PARTIES.get(row[13].strip(), "OTH"))
        votes[key] = votes.get(key, 0) + int(row[17])
        if row[16].strip() == "Y":
            elected.add(key)
    results = [dict(riding=riding, party=party, votes=count, elected=int((riding, party) in elected))
               for (riding, party), count in votes.items()]
    return list(ridings.values()), results


def parse_winners(body):
    """The elected candidate per riding: family and first name, for matching MPs in watch."""
    winners = {}
    for row in _rows(body):
        if row[16].strip() == "Y":
            winners.setdefault(row[0].strip(), dict(riding=row[0].strip(), family=row[10].strip(), first=row[12].strip()))
    return list(winners.values())


# Elections Canada Table 12 names parties in the English part of "Candidate/Candidat" (text before the last "/").
TABLE12_PARTIES = (("NDP-New Democratic Party", "NDP"), ("Liberal", "LPC"), ("Conservative", "CPC"),
                   ("Bloc Québécois", "BQ"), ("Green Party", "GPC"), ("People's Party - PPC", "PPC"))
TABLE12_NUMBER = "Electoral District Number/Numéro de circonscription"
TABLE12_CANDIDATE = "Candidate/Candidat"
TABLE12_VOTES = "Votes Obtained/Votes obtenus"


def _table12_party(candidate):
    english = candidate.rsplit("/", 1)[0].strip()
    for suffix, party in TABLE12_PARTIES:
        if english.endswith(suffix):
            return party
    return "OTH"


def parse_table12(body):
    """Elections Canada Table 12 (results by candidate) -> {riding: {"region", "votes": {party: int}}}."""
    ridings = {}
    for row in csv.DictReader(io.StringIO(body.decode("utf-8-sig"))):
        number = row[TABLE12_NUMBER].strip()
        if number[:2] not in PROVINCES:
            raise ValueError("unknown district number " + number)
        riding = ridings.setdefault(number, dict(region=PROVINCES[number[:2]][1], votes={}))
        party = _table12_party(row[TABLE12_CANDIDATE])
        riding["votes"][party] = riding["votes"].get(party, 0) + int(row[TABLE12_VOTES])
    return ridings


def results_from_db(db, election=ELECTION):
    """The same shape as parse_table12, from the ridings and riding_results tables."""
    ridings = {}
    for row in db.execute("SELECT r.id, r.region, rr.party, rr.votes FROM ridings r "
                          "JOIN riding_results rr ON rr.riding = r.id WHERE rr.election = ?", (election,)):
        riding = ridings.setdefault(row["id"], dict(region=row["region"], votes={}))
        riding["votes"][row["party"]] = row["votes"]
    return ridings


def load_results(data_dir, fetch, now, force=False):
    try:
        with connect(data_dir) as db:
            loaded = db.execute("SELECT EXISTS(SELECT 1 FROM riding_results WHERE election=?) AND "
                                "EXISTS(SELECT 1 FROM riding_winners WHERE election=?)", (ELECTION, ELECTION)).fetchone()[0]
        if loaded and not force:
            return True
        body = fetch(URL)
        store_raw(data_dir, "ec_results", body, now)
        ridings, results = parse_results(body)
        winners = parse_winners(body)
        with connect(data_dir) as db, db:
            db.execute("BEGIN IMMEDIATE")
            db.execute("DELETE FROM ridings")
            db.executemany("INSERT INTO ridings VALUES (:id,:name_en,:name_fr,:province,:region)", ridings)
            db.execute("DELETE FROM riding_results WHERE election=?", (ELECTION,))
            db.executemany("INSERT INTO riding_results VALUES (:riding,:election,:party,:votes,:elected)",
                           [dict(row, election=ELECTION) for row in results])
            db.execute("DELETE FROM riding_winners WHERE election=?", (ELECTION,))
            db.executemany("INSERT INTO riding_winners VALUES (:riding,:election,:family,:first)",
                           [dict(row, election=ELECTION) for row in winners])
            set_meta(db, "source:ec_results", json.dumps(dict(at=iso(now), ok=True, error=None)))
        return True
    except Exception as exc:
        with connect(data_dir) as db, db:
            set_meta(db, "source:ec_results", json.dumps(dict(at=iso(now), ok=False, error=str(exc) or type(exc).__name__)))
        return False


def main(argv=None):
    parser = argparse.ArgumentParser(description="Load Elections Canada 2025 riding results")
    parser.add_argument("--data", default=DEFAULT_DATA)
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args(argv)
    ok = load_results(args.data, fetch, datetime.now(timezone.utc), force=args.force)
    sys.stderr.write("ec_results %s\n" % ("ok" if ok else "failed"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
