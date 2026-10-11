"""Measure caption speaker guesses against aligned official interventions."""

import argparse
from bisect import bisect_right
from datetime import datetime
import json

from watch.align import align
from watch.records import _normal
from watch.speaker import PRESIDING
from watch.store import DEFAULT_DATA, connect


def measure(db, event_id):
    event_id = str(event_id)
    event = db.execute('SELECT * FROM events WHERE id=?', (event_id,)).fetchone()
    if event is None:
        raise ValueError('unknown event: ' + event_id)
    if not db.execute('SELECT 1 FROM documents WHERE id=?', (event['document'],)).fetchone():
        raise ValueError('official document is not stored: ' + event['document'])
    meta = db.execute('SELECT value FROM meta WHERE key=?', ('segment:' + event_id,)).fetchone()
    caption_rows = db.execute('SELECT * FROM paragraphs WHERE document=? ORDER BY position', ('captions/' + event_id,)).fetchall()
    if meta is None or not caption_rows:
        raise ValueError('caption paragraphs are not stored: ' + event_id)
    state = json.loads(meta[0])
    grouped = {}
    for row in db.execute('SELECT * FROM paragraphs WHERE document=? ORDER BY position', (event['document'],)):
        item = grouped.setdefault(row['intervention'], dict(id=row['intervention'], at=row['at'], text='',
                                                           person=row['person_id'], speaker=row['speaker']))
        item['text'] = (item['text'] + ' ' + row['text_en']).strip()
    interventions = list(grouped.values())
    lines = db.execute("SELECT begin,text FROM captions WHERE event=? AND lang='en' AND source=? ORDER BY seq",
                       (event_id, state['source'])).fetchall()
    matched = align(interventions, lines)
    guesses = {row['intervention']: row['person_id'] for row in caption_rows}
    spans = state['speeches']
    begins = [datetime.fromisoformat(span['begin']).timestamp() for span in spans]
    result = dict(event=event_id, document=event['document'], interventions=len(interventions),
                  aligned=sum(value is not None for value in matched.values()), evaluable=0, guessed=0, correct=0,
                  precision=None, recall=None, by_how={how: dict(guessed=0, correct=0) for how in ('riding', 'portfolio', 'surname')}, errors=[])
    for item in interventions:
        match = matched[item['id']]
        presiding = any(_normal(item['speaker'] or '').startswith(_normal(name)) for name in PRESIDING)
        if match is None or item['person'] is None or presiding:
            continue
        result['evaluable'] += 1
        when = datetime.fromisoformat(match).timestamp()
        position = bisect_right(begins, when) - 1
        span = spans[position] if position >= 0 else None
        if span is not None and when > datetime.fromisoformat(span['end']).timestamp():
            span = None
        guess = guesses.get(span['id']) if span else None
        how = span['how'] if span else None
        if guess is not None:
            result['guessed'] += 1
            result['by_how'][how]['guessed'] += 1
            if guess == item['person']:
                result['correct'] += 1
                result['by_how'][how]['correct'] += 1
        if guess != item['person'] and len(result['errors']) < 20:
            result['errors'].append(dict(intervention=item['id'], expected=item['person'], guessed=guess,
                                         how=how, text=item['text'][:240]))
    for field, divisor in (('precision', 'guessed'), ('recall', 'evaluable')):
        if result[divisor]:
            result[field] = result['correct'] / result[divisor]
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description='Measure caption speaker accuracy against official records')
    parser.add_argument('--data', default=DEFAULT_DATA)
    parser.add_argument('--event', action='append', required=True)
    args = parser.parse_args(argv)
    with connect(args.data) as db:
        for event in args.event:
            print(json.dumps(measure(db, event)))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
