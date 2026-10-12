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


def parse_results(body):
    ridings, votes, elected = {}, {}, set()
    with zipfile.ZipFile(io.BytesIO(body)) as archive:
        for name in archive.namelist():
            if not name.endswith(".csv"):
                continue
            rows = csv.reader(io.StringIO(archive.read(name).decode("utf-8-sig")))
            next(rows)
            for row in rows:
                if not row:
                    continue
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


def load_results(data_dir, fetch, now, force=False):
    try:
        with connect(data_dir) as db:
            loaded = db.execute("SELECT 1 FROM riding_results WHERE election=? LIMIT 1", (ELECTION,)).fetchone()
        if loaded and not force:
            return True
        body = fetch(URL)
        store_raw(data_dir, "ec_results", body, now)
        ridings, results = parse_results(body)
        with connect(data_dir) as db, db:
            db.execute("BEGIN IMMEDIATE")
            db.execute("DELETE FROM ridings")
            db.executemany("INSERT INTO ridings VALUES (:id,:name_en,:name_fr,:province,:region)", ridings)
            db.execute("DELETE FROM riding_results WHERE election=?", (ELECTION,))
            db.executemany("INSERT INTO riding_results VALUES (:riding,:election,:party,:votes,:elected)",
                           [dict(row, election=ELECTION) for row in results])
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
