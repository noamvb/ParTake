"""Rules and incremental embedding for Parliament watch.

meta match:follow:<id> stores a canonical kind/object signature. A changed
signature invalidates that follow's matches; unchanged phrases reuse vectors. Rules scan all
history so late ballots and out-of-order intervention paragraphs converge;
sync prunes displaced MP first paragraphs. A paragraph is topic-scored when
its vector is stored; only new or edited topics (or ones whose phrase vectors
were just embedded after a failure) re-score stored history.
meta backfill stores {done, total} for embeddable paragraphs. Each completed
embedding batch commits its vectors, matches and progress together.
"""

import json
import re

from watch import embed, store


def floor_text(row):
    primary, other = ('text_en', 'text_fr') if row['lang'] == 'en' else ('text_fr', 'text_en')
    return row[primary] or row[other] or ''


def embeddable(row):
    return len(floor_text(row).split()) >= 8


def _add(db, follow, kind, item, score, at):
    cursor = db.execute('INSERT OR IGNORE INTO matches VALUES (?,?,?,?,?)',
                        (follow, kind, str(item), score, at))
    return cursor.rowcount


def _keyword(obj, row):
    return any(keyword and re.search(r'(?<!\w)' + re.escape(keyword) + r'(?!\w)',
                                    row['text_en'] + '\n' + row['text_fr'], re.I)
               for keyword in obj['keywords'])


def _bill_pattern(number):
    parts = re.split(r'[-\u2010\u2011\s]+', number)
    return re.compile(r'(?<!\w)' + r'[-\u2010\u2011 ]'.join(map(re.escape, parts)) + r'(?!\w)', re.I)


def _first_paragraphs(db, people):
    """Ids of each intervention's first paragraph spoken by one of people."""
    if not people:
        return {}
    marks = ','.join('?' * len(people))
    return {row['id']: (row['person_id'], row['at']) for row in db.execute(
        'SELECT p.id,p.person_id,p.at FROM paragraphs p JOIN (SELECT document,intervention,min(position) AS m '
        'FROM paragraphs WHERE person_id IN (%s) GROUP BY document,intervention) f '
        'ON p.document=f.document AND p.intervention=f.intervention AND p.position=f.m' % marks, list(people))}


def match_rules(db):
    """Add all current rule matches without deleting any existing matches.

    Paragraph text is streamed, never held in memory, so this scales to the
    full backfill.
    """
    rules = [(f['id'], f['kind'], f[f['kind']]) for f in store.list_follows(db)['follows']
             if f['kind'] in ('topic', 'bill', 'mp', 'votes')]
    if not rules:
        return 0
    found = []
    text_rules = [(fid, kind, obj, _bill_pattern(obj['number']) if kind == 'bill' else None)
                  for fid, kind, obj in rules if kind == 'bill' or (kind == 'topic' and obj['keywords'])]
    if text_rules:
        for row in db.execute('SELECT id,at,text_en,text_fr FROM paragraphs'):
            for fid, kind, obj, pattern in text_rules:
                if (_keyword(obj, row) if kind == 'topic' else
                        pattern.search(row['text_en'] + '\n' + row['text_fr'])):
                    found.append((fid, 'paragraph', row['id'], row['at']))
    people = {}
    for fid, kind, obj in rules:
        if kind == 'mp':
            people.setdefault(obj['person_id'], []).append(fid)
    for pid, (person, at) in _first_paragraphs(db, people).items():
        found.extend((fid, 'paragraph', pid, at) for fid in people[person])
    ballots, split = {}, set()
    parties = {}
    for row in db.execute('SELECT division,person_id,party,vote FROM ballots'):
        ballots.setdefault(row['division'], set()).add(row['person_id'])
        if row['vote'] in ('yea', 'nay'):
            votes = parties.setdefault((row['division'], row['party']), set())
            votes.add(row['vote'])
            if len(votes) == 2:
                split.add(row['division'])
    for row in db.execute('SELECT id,bill,at FROM divisions'):
        for fid, kind, obj in rules:
            if (kind == 'bill' and row['bill'] == obj['id'] or
                    kind == 'mp' and obj['person_id'] in ballots.get(row['id'], ()) or
                    kind == 'votes' and (obj['filter'] == 'all' or row['id'] in split)):
                found.append((fid, 'division', row['id'], row['at']))
    for row in db.execute('SELECT id,bill,at FROM bill_stages'):
        for fid, kind, obj in rules:
            if kind == 'bill' and row['bill'] == obj['id']:
                found.append((fid, 'bill_stage', row['id'], row['at']))
    return sum(_add(db, fid, kind, item, 1.0, at) for fid, kind, item, at in found)


def _topic_match(db, rows, topics):
    added = 0
    for row in rows:
        vector = embed.unpack(row['vec'])
        for follow, phrases in topics:
            obj = follow['topic']
            score = 1.0 if _keyword(obj, row) else max(
                (embed.dot(vector, phrase) for phrase in phrases), default=-1.0)
            if score >= obj['threshold']:
                added += _add(db, follow['id'], 'paragraph', row['id'], score, row['at'])
    return added


def _backfill(db, done, total):
    store.set_meta(db, 'backfill', json.dumps({'done': done, 'total': total}))


def sync(db, embedder, batch=32, max_batches=None):
    if batch < 1 or (max_batches is not None and max_batches < 0):
        raise ValueError('invalid batch count')
    result = {'embedded': 0, 'matches_added': 0}
    active = store.list_follows(db)['follows']
    failed = False
    refresh = set()  # topic follows whose history must be re-scored
    for follow in active:
        fid, kind = follow['id'], follow['kind']
        signature = json.dumps([kind, follow.get(kind)], sort_keys=True)
        key = 'match:follow:' + fid
        old = db.execute('SELECT value FROM meta WHERE key=?', (key,)).fetchone()
        if old is None or old[0] != signature:
            refresh.add(fid)
            db.execute('DELETE FROM matches WHERE follow=?', (fid,))
            if kind != 'topic':
                db.execute('DELETE FROM follow_vectors WHERE follow=?', (fid,))
            else:
                for row in db.execute('SELECT lang,phrase FROM follow_vectors WHERE follow=?', (fid,)).fetchall():
                    if follow['topic']['phrases'].get(row['lang']) != row['phrase']:
                        db.execute('DELETE FROM follow_vectors WHERE follow=? AND lang=?', (fid, row['lang']))
            store.set_meta(db, key, signature)
        if kind == 'topic' and not failed:
            obj = follow['topic']
            missing = [(lang, phrase) for lang, phrase in obj['phrases'].items() if phrase and not
                       db.execute('SELECT 1 FROM follow_vectors WHERE follow=? AND lang=? AND phrase=? AND model=?',
                                  (fid, lang, phrase, embed.MODEL)).fetchone()]
            if missing:
                try:
                    vectors = embedder([phrase for lang, phrase in missing])
                    if len(vectors) != len(missing):
                        raise embed.EmbedError('embedding count mismatch')
                    refresh.add(fid)
                    for (lang, phrase), vector in zip(missing, vectors):
                        db.execute('INSERT OR REPLACE INTO follow_vectors VALUES (?,?,?,?,?)',
                                   (fid, lang, phrase, embed.MODEL, embed.pack(vector)))
                except embed.EmbedError as exc:
                    result['embed_error'] = str(exc)
                    failed = True
        if kind == 'mp':
            first = _first_paragraphs(db, {follow['mp']['person_id']: [fid]})
            stale = [r[0] for r in db.execute("SELECT item_id FROM matches WHERE follow=? AND item_kind='paragraph'",
                                              (fid,)) if r[0] not in first]
            db.executemany('DELETE FROM matches WHERE follow=? AND item_kind=? AND item_id=?',
                           [(fid, 'paragraph', item) for item in stale])
    result['matches_added'] += match_rules(db)
    topics = [(f, [embed.unpack(r[0]) for r in db.execute(
        'SELECT vec FROM follow_vectors WHERE follow=? AND model=?', (f['id'], embed.MODEL))])
        for f in active if f['kind'] == 'topic']
    # Paragraphs embedded earlier were scored against unchanged topics when
    # their vectors were stored; only new or edited topics revisit history.
    stale_topics = [t for t in topics if t[0]['id'] in refresh]
    if stale_topics:
        result['matches_added'] += _topic_match(db, db.execute(
            'SELECT p.id,p.at,p.text_en,p.text_fr,v.vec FROM paragraphs p JOIN vectors v ON v.paragraph=p.id '
            'WHERE v.model=?', (embed.MODEL,)), stale_topics)
    done = db.execute('SELECT count(*) FROM vectors').fetchone()[0]
    total, pending = 0, []
    for row in db.execute('SELECT p.id,p.lang,p.text_en,p.text_fr,v.paragraph IS NULL AS missing FROM paragraphs p '
                          'LEFT JOIN vectors v ON v.paragraph=p.id ORDER BY p.at DESC,p.seq DESC'):
        if embeddable(row):
            total += 1
            if row['missing']:
                pending.append(row['id'])
    _backfill(db, done, total)
    db.commit()
    for start in range(0, len(pending), batch):
        if failed or (max_batches is not None and start//batch >= max_batches):
            break
        ids = pending[start:start+batch]
        by_id = {r['id']: r for r in db.execute(
            'SELECT * FROM paragraphs WHERE id IN (%s)' % ','.join('?' * len(ids)), ids)}
        rows = [by_id[i] for i in ids]
        try:
            vectors = embedder([floor_text(r) for r in rows])
            if len(vectors) != len(rows):
                raise embed.EmbedError('embedding count mismatch')
        except embed.EmbedError as exc:
            result['embed_error'] = str(exc)
            break
        with db:
            packed_rows = []
            for row, vector in zip(rows, vectors):
                blob = embed.pack(vector)
                db.execute('INSERT INTO vectors VALUES (?,?,?)', (row['id'], embed.MODEL, blob))
                packed_rows.append(dict(row, vec=blob))
            result['matches_added'] += _topic_match(db, packed_rows, topics)
            result['embedded'] += len(rows)
            done += len(rows)
            _backfill(db, done, total)
    return result
