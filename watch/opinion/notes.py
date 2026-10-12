"""Weekly what-changed note, written by fixed rules from the projection numbers (no LLM), and the new-poll counts behind it."""

from datetime import date, datetime, timedelta, timezone
import json
from zoneinfo import ZoneInfo

from watch.store import iso


OTTAWA = ZoneInfo("America/Toronto")
# Model parties only: OTH is never named.
NAMES = {"LPC": "Liberals", "CPC": "Conservatives", "NDP": "NDP", "BQ": "Bloc", "GPC": "Greens"}
ADJECTIVES = {"LPC": "Liberal", "CPC": "Conservative", "NDP": "NDP", "BQ": "Bloc", "GPC": "Green"}
MOVE = 0.5


def change(value):
    return "no change" if value == 0 else "%+d" % value


def _movers(prev, cur):
    before, after = prev["average"]["CAN"], cur["average"]["CAN"]
    moves = []
    for party in NAMES:
        change = round(after[party] - before[party], 1)
        if abs(change) >= MOVE:
            moves.append((abs(change), party, change, after[party]))
    if not moves:
        return "Little change in the polls."
    moves.sort(key=lambda move: -move[0])
    return ", ".join("%s %s %.1f points to %.1f%%" % (NAMES[party], "up" if change > 0 else "down", size, value)
                     for size, party, change, value in moves) + "."


def _seats(prev, cur):
    counts, before = cur["seats"]["CAN"], prev["seats"]["CAN"]
    first, second = _leaders(cur)
    return "Projection: %s %d seats (%s), %s %d (%s)." % (
        NAMES[first], counts[first], change(counts[first] - before[first]),
        NAMES[second], counts[second], change(counts[second] - before[second]))


def _leaders(body):
    # Stable sort: ties keep the order of NAMES.
    return sorted(NAMES, key=lambda party: -body["seats"]["CAN"][party])[:2]


def _odds(prev, cur):
    party = _leaders(cur)[0]
    now = round(cur["sim"]["majority"][party] * 100)
    was = round(prev["sim"]["majority"][party] * 100)
    return "%s majority odds %d%% (%s)." % (ADJECTIVES[party], now, change(now - was))


def _polls(new_polls):
    if new_polls == 0:
        return "No new polls this week."
    if new_polls == 1:
        return "1 new poll this week."
    return "%d new polls this week." % new_polls


def week_note(prev, cur, new_polls):
    """The note for one week from its last projection (cur) and the one a week earlier (prev)."""
    sentences = [_movers(prev, cur), _seats(prev, cur)]
    if "sim" in prev and "sim" in cur:
        sentences.append(_odds(prev, cur))
    sentences.append(_polls(new_polls))
    return " ".join(sentences)


def _ottawa_date(stamp):
    return datetime.fromisoformat(stamp).astimezone(OTTAWA).date()


def new_polls_by_day(db):
    """CAN polls per Ottawa date first seen. The backfill day (the earliest first_seen in the table) never counts."""
    rows = db.execute("SELECT region, first_seen FROM opinion_polls WHERE first_seen IS NOT NULL").fetchall()
    if not rows:
        return {}
    backfill = min(_ottawa_date(row["first_seen"]) for row in rows)
    counts = {}
    for row in rows:
        day = _ottawa_date(row["first_seen"])
        if row["region"] == "CAN" and day != backfill:
            counts[day.isoformat()] = counts.get(day.isoformat(), 0) + 1
    return counts


def write_notes(db, today):
    """Upsert the note for each complete Monday-Sunday week before today that has projections for its Sunday and the Sunday before."""
    bodies = {row["date"]: json.loads(row["body"]) for row in db.execute("SELECT date, body FROM projections")}
    # Polls by field end date: the backfill saw every past poll on one day, so first-seen dates
    # would leave every earlier week with "No new polls".
    polls = dict(db.execute("SELECT end_date, COUNT(*) FROM opinion_polls WHERE region='CAN' GROUP BY end_date"))
    created_at = iso(datetime.now(timezone.utc))
    for day in sorted(bodies):
        sunday = date.fromisoformat(day)
        if sunday.weekday() != 6 or sunday >= today:
            continue
        before = (sunday - timedelta(days=7)).isoformat()
        if before not in bodies:
            continue
        monday = (sunday - timedelta(days=6)).isoformat()
        new_polls = sum(count for seen, count in polls.items() if monday <= seen <= day)
        text = week_note(bodies[before], bodies[day], new_polls)
        db.execute("INSERT INTO opinion_notes VALUES (?,?,?) ON CONFLICT(week_of) DO UPDATE SET "
                   "text=excluded.text, created_at=excluded.created_at", (monday, text, created_at))
