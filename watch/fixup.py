"""Replace caption paragraphs and align official speeches to their recording."""

from datetime import datetime, timedelta
import json

from watch import align, store


def fixup(db, now):
    totals = dict(superseded=0, aligned=0, fallback=0, interventions=0)
    documents = db.execute("SELECT e.* FROM documents d JOIN events e ON e.document=d.id "
                           "WHERE d.source IN ('hansard','evidence') AND NOT EXISTS "
                           "(SELECT 1 FROM meta WHERE key='fixup:' || d.id) ORDER BY d.id,e.id").fetchall()
    for event in documents:
        document = event['document']
        if db.execute('SELECT 1 FROM meta WHERE key=?', ('fixup:' + document,)).fetchone():
            continue
        event_id = event['id']
        source = 'archive' if db.execute("SELECT 1 FROM captions WHERE event=? AND source='archive' LIMIT 1", (event_id,)).fetchone() else 'live'
        lines = db.execute('SELECT * FROM captions WHERE event=? AND source=? ORDER BY seq', (event_id, source)).fetchall()
        end = datetime.fromisoformat(event['actual_end'] or event['scheduled_start'])
        if not lines and now - end < timedelta(hours=48):
            continue
        interventions = {}
        for row in db.execute('SELECT * FROM paragraphs WHERE document=? ORDER BY position', (document,)):
            speech = interventions.setdefault(row['intervention'], dict(id=row['intervention'], at=row['at'], text=''))
            speech['text'] = (speech['text'] + ' ' + row['text_en']).strip()
        matches = align.align(list(interventions.values()), lines)
        counts = dict(superseded=0, aligned=0, fallback=0, interventions=len(interventions))
        base = None
        if event['recording_start'] is not None and event['preroll_s'] is not None:
            base = datetime.fromisoformat(event['recording_start']) - timedelta(seconds=event['preroll_s'])
        with db:
            counts['superseded'] = db.execute("UPDATE paragraphs SET superseded_by=? WHERE source='captions' AND event_id=?",
                                               (document, event_id)).rowcount
            for iid, speech in interventions.items():
                at = matches[iid]
                how = 'aligned'
                if at is None:
                    if event['actual_start'] is None or event['actual_end'] is None:
                        continue
                    moment = datetime.fromisoformat(speech['at'])
                    if not datetime.fromisoformat(event['actual_start']) <= moment <= datetime.fromisoformat(event['actual_end']):
                        continue
                    at, how = speech['at'], 'fallback'
                offset = round((datetime.fromisoformat(at) - base).total_seconds(), 3) if base is not None else None
                db.execute('UPDATE paragraphs SET event_id=?,offset_s=? WHERE document=? AND intervention=?',
                           (event_id, offset, document, iid))
                counts[how] += 1
            store.set_meta(db, 'fixup:' + document, json.dumps(dict(at=store.iso(now), **counts)))
        for key in totals:
            totals[key] += counts[key]
    return totals
