"""Render matched Parliament records and stable opaque feed cursors."""

import base64
import json
import re

from watch import store
from watch.match import floor_text


KINDS = {'paragraph': 'speech', 'division': 'division', 'bill_stage': 'bill_stage'}


def _legisinfo(bill):
    return 'https://www.parl.ca/legisinfo/en/bill/' + bill.lower() if bill else None


def _speaker(db, row):
    if row['speaker'] is None:
        return None
    member = db.execute('SELECT name,party FROM members WHERE person_id=?', (row['person_id'],)).fetchone()
    if member:
        name, party = member
    else:
        name = re.sub(r'\([^()]*\)', '', row['speaker'])
        name = re.sub(r'^\s*(?:Right Hon\.|Hon\.|Mr\.|Mrs\.|Ms\.|Miss\b|Dr\.|The\b)\s*', '', name)
        name, party = ' '.join(name.split()), None
    return {'person_id': row['person_id'], 'name': name, 'party': party,
            'confidence': 1.0, 'from': row['source']}


def _item(db, kind, iid, at, matched, active):
    public_kind = KINDS[kind]
    item = dict(id='m_' + {'paragraph': 's', 'division': 'd', 'bill_stage': 'b'}[kind] + '_' +
                (iid.replace('/', '-') if kind == 'division' else iid), kind=public_kind, at=at,
                follows=matched, source=None, superseded=False, title=None, text=None,
                lang='en', speaker=None, video=None,
                links={'hansard': None, 'legisinfo': None, 'division': None}, division=None, bill_stage=None)
    if kind == 'paragraph':
        row = db.execute('SELECT * FROM paragraphs WHERE id=?', (iid,)).fetchone()
        item.update(source=row['source'], title=row['title'], text=floor_text(row), lang=row['lang'],
                    speaker=_speaker(db, row))
        document = db.execute('SELECT url FROM documents WHERE id=?', (row['document'],)).fetchone()
        item['links']['hansard'] = document[0] + '#Para' + iid[1:] if document else None
    elif kind == 'division':
        row = db.execute('SELECT * FROM divisions WHERE id=?', (iid,)).fetchone()
        result = {'agreed': 'Agreed to', 'negatived': 'Negatived', 'tie': 'Tie'}.get(row['result'], row['result'])
        item.update(source='votes', title='Vote %d: %s' % (row['number'], result), text=row['description'])
        session = iid.split('/')[0].replace('-', '/')
        item['links'].update(legisinfo=_legisinfo(row['bill']),
                             division='https://www.ourcommons.ca/Members/en/votes/%s/%s' % (session, row['number']))
        division = {k: row[k] for k in ('id', 'number', 'bill', 'description', 'result', 'yeas', 'nays', 'paired')}
        parties, mps = {}, []
        people = {f['mp']['person_id'] for f in active if f['kind'] == 'mp'}
        for ballot in db.execute('SELECT * FROM ballots WHERE division=? ORDER BY person_id', (iid,)):
            party = parties.setdefault(ballot['party'], {'party': ballot['party'], 'yea': 0, 'nay': 0})
            if ballot['vote'] in ('yea', 'nay'):
                party[ballot['vote']] += 1
            if ballot['person_id'] in people:
                mps.append({'person_id': ballot['person_id'], 'vote': ballot['vote']})
        for party in parties.values():
            party['split'] = party['yea'] > 0 and party['nay'] > 0
        division.update(parties=[parties[p] for p in sorted(parties)], mps=mps)
        item['division'] = division
    else:
        row = db.execute('SELECT * FROM bill_stages WHERE id=?', (iid,)).fetchone()
        bill = db.execute('SELECT number,title FROM bills WHERE id=?', (row['bill'],)).fetchone()
        number = bill['number'] if bill else row['bill'].split('/')[-1]
        chamber = 'House of Commons' if row['chamber'] == 'house' else 'Senate'
        item.update(source='legisinfo', title='%s: %s (%s)' % (number, row['stage'], chamber),
                    text=bill['title'] if bill else number)
        item['links']['legisinfo'] = _legisinfo(row['bill'])
        item['bill_stage'] = dict(bill=row['bill'], number=number, stage=row['stage'], chamber=row['chamber'], at=row['at'])
    return item


def _cursor(key):
    return base64.urlsafe_b64encode(json.dumps(key).encode()).decode().rstrip('=')


def _decode(cursor):
    try:
        key = json.loads(base64.b64decode(cursor + '=' * (-len(cursor) % 4), altchars=b'-_', validate=True))
        if (not isinstance(key, list) or len(key) != 3 or
                not all(isinstance(x, str) and x for x in key) or key[1] not in KINDS):
            raise ValueError()
        return tuple(key)
    except Exception as exc:
        raise ValueError('malformed cursor') from exc


def feed(db, follows=None, kind=None, limit=50, before=None):
    if type(limit) is not int or not 1 <= limit <= 200:
        raise ValueError('limit must be between 1 and 200')
    if kind is not None and kind not in KINDS.values():
        raise ValueError('unknown kind')
    active = store.list_follows(db)['follows']
    active_ids = {f['id'] for f in active}
    selected = active_ids if follows is None else set(follows)
    if not selected <= active_ids:
        raise ValueError('unknown active follow')
    cursor = _decode(before) if before is not None else None
    groups = {}
    for row in db.execute('SELECT * FROM matches'):
        if row['follow'] in active_ids:
            key = (row['at'], row['item_kind'], row['item_id'])
            groups.setdefault(key, {})[row['follow']] = row['score']
    # Descending in all three fields is a fixed tie order and keeps the SQL
    # storage kind in the cursor rather than relying on rendered item ids.
    keys = sorted((k for k, values in groups.items() if selected.intersection(values) and
                   (kind is None or KINDS[k[1]] == kind) and (cursor is None or k < cursor)), reverse=True)
    items = []
    for at, storage_kind, iid in keys[:limit]:
        scores = groups[(at, storage_kind, iid)]
        matched = [{'id': f['id'], 'score': round(scores[f['id']], 3)} for f in active if f['id'] in scores]
        items.append(_item(db, storage_kind, iid, at, matched, active))
    return {'items': items, 'next': _cursor(keys[limit-1]) if len(keys) > limit else None}
