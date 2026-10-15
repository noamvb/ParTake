"""Read-only PMO response objects shared by the watch HTTP routes."""

import base64
from datetime import date, timedelta
import json
import re

from watch.pm.itinerary import parse_itinerary
from watch.pm.sources import OTTAWA, itinerary_date
from watch.store import iso


PLACE_KEYS = ('id', 'name', 'country', 'lat', 'lon', 'zone')
ITEM_KEYS = ('id', 'type', 'title', 'published_at', 'url')


def _place(db, key):
    row = db.execute('SELECT * FROM pm_places WHERE id=?', (key,)).fetchone()
    return {k: row[k] for k in PLACE_KEYS} if row else None


def _event(db, row):
    return dict(date=row['date'], local_time=row['local_time'], starts_at=row['starts_at'],
                place=_place(db, row['place_id']), text=row['text'], venue=row['venue'],
                media=row['media'], item_id=row['item_id'])


def today(db, now):
    day = now.astimezone(OTTAWA).date()
    dates = (day.isoformat(), (day + timedelta(days=1)).isoformat())
    winners = {}
    for row in db.execute("SELECT * FROM pm_items WHERE type='itinerary' ORDER BY published_at,id"):
        try:
            item_day = itinerary_date(row['title'])
        except ValueError:
            continue
        if item_day in dates:
            winners[item_day] = row
    days = []
    for item_day in dates:
        if item_day not in winners:
            continue
        row = winners[item_day]
        events = [_event(db, e) for e in db.execute('SELECT * FROM pm_events WHERE item_id=? ORDER BY seq', (row['id'],))]
        days.append(dict(date=item_day, item_id=row['id'], url=row['url'],
                         notes=parse_itinerary(row['body_html'])['notes'], events=events))
    current = db.execute('SELECT * FROM pm_events WHERE date=? AND starts_at<=? '
                         'ORDER BY starts_at DESC,seq DESC LIMIT 1', (dates[0], iso(now))).fetchone()
    following = db.execute('SELECT * FROM pm_events WHERE starts_at>? ORDER BY starts_at,date,seq LIMIT 1',
                           (iso(now),)).fetchone()
    last = current or db.execute('SELECT * FROM pm_events WHERE date<=? ORDER BY date DESC,seq DESC LIMIT 1',
                                (dates[0],)).fetchone()
    fetched = db.execute('SELECT max(fetched_at) FROM pm_items').fetchone()[0]
    return dict(days=days, now=dict(place=_place(db, last['place_id']) if last else None,
                                   event=_event(db, current) if current else None),
                next=_event(db, following) if following else None, fetched_at=fetched)


def _summary(text):
    if len(text) <= 280:
        return text
    return text[:280].rsplit(' ', 1)[0] + '…'


def feed(db, limit=50, before=None, type=None):
    if not 1 <= limit <= 200:
        raise ValueError('limit must be between 1 and 200')
    where, params = ['1'], []
    if type is not None:
        kinds = type.split(',')
        if any(k not in ('itinerary', 'readout', 'release', 'statement', 'speech', 'backgrounder', 'other') for k in kinds):
            raise ValueError('unknown PM item type')
        where.append('type IN (%s)' % ','.join('?' for _ in kinds))
        params.extend(kinds)
    if before is not None:
        try:
            stamp, key = json.loads(base64.urlsafe_b64decode(before.encode()))
            if not isinstance(stamp, str) or not isinstance(key, str):
                raise ValueError('invalid cursor')
        except Exception as exc:
            raise ValueError('invalid cursor') from exc
        where.append('(published_at,id)<(?,?)')
        params.extend((stamp, key))
    rows = db.execute('SELECT * FROM pm_items WHERE ' + ' AND '.join(where) +
                      ' ORDER BY published_at DESC,id DESC LIMIT ?', params + [limit + 1]).fetchall()
    page = rows[:limit]
    items = [dict({k: row[k] for k in ITEM_KEYS}, summary=_summary(row['text'])) for row in page]
    cursor = None
    if len(rows) > limit:
        cursor = base64.urlsafe_b64encode(json.dumps([page[-1]['published_at'], page[-1]['id']]).encode()).decode()
    return dict(items=items, next=cursor,
                source=dict(name="Prime Minister's Office", url='https://www.pm.gc.ca/en/news'))


def item(db, key):
    row = db.execute('SELECT * FROM pm_items WHERE id=?', (key,)).fetchone()
    if row is None:
        return None
    return dict({k: row[k] for k in ITEM_KEYS}, body=row['body_html'], text=row['text'],
                events=[_event(db, e) for e in db.execute('SELECT * FROM pm_events WHERE item_id=? ORDER BY seq', (key,))])


def _range(since, until, now, required=False):
    if required and (since is None or until is None):
        raise ValueError('since and until required')
    since = since if since is not None else '2025-03-14'
    until = until if until is not None else now.astimezone(OTTAWA).date().isoformat()
    for value in (since, until):
        if not re.fullmatch(r'\d{4}-\d{2}-\d{2}', value):
            raise ValueError('invalid date')
    first, last = date.fromisoformat(since), date.fromisoformat(until)
    if last < first or (required and (last - first).days > 31):
        raise ValueError('invalid date range')
    return since, until


def places(db, since, until, now):
    since, until = _range(since, until, now)
    result = []
    for row in db.execute('SELECT place_id,count(*) AS visits,count(DISTINCT date) AS days,'
                          'min(date) AS first,max(date) AS last FROM pm_events WHERE date BETWEEN ? AND ? '
                          'GROUP BY place_id ORDER BY place_id', (since, until)):
        result.append(dict(_place(db, row['place_id']), **{k: row[k] for k in ('visits', 'days', 'first', 'last')}))
    return dict(places=result, since=since, until=until)


def path(db, since, until, now):
    since, until = _range(since, until, now, required=True)
    stops = []
    for row in db.execute('SELECT * FROM pm_events WHERE date BETWEEN ? AND ? ORDER BY date,local_time,item_id,seq', (since, until)):
        if stops and stops[-1]['place']['id'] == row['place_id']:
            stops[-1]['events'] += 1
        else:
            stops.append(dict(date=row['date'], place=_place(db, row['place_id']),
                              first_time=row['local_time'], events=1))
    return dict(stops=stops, since=since, until=until)
