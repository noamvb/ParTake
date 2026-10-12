"""Build saved feed snapshots for Ottawa sitting dates."""

import argparse
from datetime import date, datetime, timedelta, timezone
import json
from zoneinfo import ZoneInfo

from watch import feed, store
from watch.opinion import notes


OTTAWA = ZoneInfo('America/Toronto')
SEAT_LINE = 10


def item_count(body):
    return len({item['id'] for section in body['sections'] for item in section['items']})


def _projection(db, day):
    row = db.execute('SELECT body FROM projections WHERE date=?', (day,)).fetchone()
    return json.loads(row[0]) if row else None


def _opinion(db, day):
    """The poll line for the evening digest: new CAN polls seen that day, and the parties projected to 10+ seats."""
    tables = {row[0] for row in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
    if not {'projections', 'opinion_polls'} <= tables:
        return None
    polls = notes.new_polls_by_day(db).get(day, 0)
    body = _projection(db, day)
    if polls == 0 or body is None:
        return None
    seats = body['seats']['CAN']
    before = _projection(db, (date.fromisoformat(day) - timedelta(days=1)).isoformat())
    parties = []
    for party in sorted(notes.NAMES, key=lambda name: -seats[name]):
        if seats[party] < SEAT_LINE:
            continue
        delta = ' (%s)' % notes.change(seats[party] - before['seats']['CAN'][party]) if before else ''
        parties.append('%s %d%s' % (party, seats[party], delta))
    text = '%d new poll%s.' % (polls, '' if polls == 1 else 's')
    if parties:
        text += ' Projection: %s.' % ', '.join(parties)
    return {'kind': 'opinion', 'text': text}


def build(db, date, kind, now):
    if kind not in ('evening', 'morning'):
        raise ValueError('unknown digest kind')
    if kind == 'morning' and not db.execute("SELECT 1 FROM documents WHERE source='hansard' AND date=?", (date,)).fetchone():
        return None
    opinion = _opinion(db, date) if kind == 'evening' else None
    active = store.list_follows(db)['follows']
    groups = feed._groups(db, active)
    sections = []
    rendered = {}
    for key in sorted(groups):
        at, storage_kind, iid = key
        if datetime.fromisoformat(at).astimezone(OTTAWA).date().isoformat() == date:
            rendered[key] = feed._item(db, storage_kind, iid, at, feed._matched(groups[key], active), active)
    for follow in active:
        items = [item for key, item in rendered.items() if follow['id'] in groups[key]]
        if items:
            sections.append(dict(follow={k: follow[k] for k in ('id', 'label')}, items=items))
    if not sections and opinion is None:
        return None
    evening = 'd_' + date + '_evening'
    replaces = evening if kind == 'morning' and db.execute('SELECT 1 FROM digests WHERE id=?', (evening,)).fetchone() else None
    body = dict(id='d_' + date + '_' + kind, date=date, kind=kind, replaces=replaces, sections=sections)
    if opinion is not None:
        body['opinion'] = opinion
    with db:
        db.execute('INSERT INTO digests VALUES (?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET '
                   'created_at=excluded.created_at,replaces=excluded.replaces,body=excluded.body',
                   (body['id'], date, kind, store.iso(now), replaces, json.dumps(body)))
    return body


def main(argv=None):
    parser = argparse.ArgumentParser(description='Build Parliament watch digests')
    parser.add_argument('--data', default=store.DEFAULT_DATA)
    parser.add_argument('--kind', required=True, choices=('evening', 'morning'))
    parser.add_argument('--date')
    parser.add_argument('--today', help=argparse.SUPPRESS)
    args = parser.parse_args(argv)
    now = datetime.now(timezone.utc)
    today = datetime.fromisoformat(args.today).date() if args.today else now.astimezone(OTTAWA).date()
    with store.connect(args.data) as db:
        if args.date:
            dates = [args.date]
        elif args.kind == 'evening':
            dates = [today.isoformat()]
        else:
            dates = [row[0] for row in db.execute("SELECT DISTINCT date FROM documents WHERE source='hansard' "
                                                "AND date>=? AND date<? AND NOT EXISTS "
                                                "(SELECT 1 FROM digests WHERE digests.date=documents.date AND kind='morning') ORDER BY date",
                                                ((today - timedelta(days=3)).isoformat(), today.isoformat()))]
        for date in dates:
            body = build(db, date, args.kind, now)
            if body:
                print(body['id'], item_count(body))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
