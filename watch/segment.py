"""Incremental caption speeches and searchable paragraphs with speaker guesses."""

from bisect import bisect_right
from datetime import datetime, timedelta
import json
import re

from watch.speaker import PRESIDING, label
from watch.store import set_meta


STATE_FIELDS = ('cursor', 'next_speech', 'next_position', 'pending', 'current')


def _paragraphs(text):
    words = list(re.finditer(r'\S+', text))
    start = 0
    while start < len(words):
        end = min(start + 200, len(words))
        for i in range(start + 119, min(start + 200, len(words))):
            word = words[i]
            if word.end() < len(text) and text[word.end()] == ' ' and word[0].endswith(('.', '?', '!')):
                end = i + 1
                break
        yield words[start].start(), ' '.join(w[0] for w in words[start:end])
        start = end


def segment_event(db, event_id, index):
    event_id = str(event_id)
    event = db.execute('SELECT * FROM events WHERE id=?', (event_id,)).fetchone()
    if event is None or event['captions'] not in ('live', 'archive'):
        return 0
    if db.execute('SELECT 1 FROM documents WHERE id=?', (event['document'],)).fetchone():
        return 0
    key = 'segment:' + event_id
    stored = db.execute('SELECT value FROM meta WHERE key=?', (key,)).fetchone()
    state = json.loads(stored[0]) if stored else None
    exists = db.execute('SELECT 1 FROM paragraphs WHERE document=? LIMIT 1', ('captions/' + event_id,)).fetchone()
    if not exists:
        archive = db.execute("SELECT 1 FROM captions WHERE event=? AND lang='en' AND source='archive' LIMIT 1", (event_id,)).fetchone()
        source = 'archive' if archive else 'live'
        if state is None or state['source'] != source:
            state = dict(source=source, cursor=dict(seq=0, offset=0), next_speech=0,
                         next_position=0, pending=None, current=None, speeches=[])
    if state is None:
        raise ValueError('caption paragraphs have no segment metadata')
    source = state['source']
    # An adjourned archive can itself be imported in batches. Its last speech
    # is complete at this snapshot, but must be extended if more rows arrive.
    finalized = state.get('finalized')
    if finalized:
        newer = db.execute("SELECT 1 FROM captions WHERE event=? AND lang='en' AND source=? AND seq>? LIMIT 1",
                           (event_id, source, finalized['last_seq'])).fetchone()
        if not newer:
            return 0
    with db:
        if finalized:
            snapshot = finalized['state']
            db.execute('DELETE FROM paragraphs WHERE document=? AND position>=?',
                       ('captions/' + event_id, snapshot['next_position']))
            state.update(snapshot)
            state['speeches'] = state['speeches'][:finalized['span_count']]
            state.pop('finalized')
        cursor = state['cursor']
        rows = db.execute("SELECT * FROM captions WHERE event=? AND lang='en' AND source=? AND seq>=? ORDER BY seq",
                          (event_id, source, cursor['seq'])).fetchall()
        if not rows:
            return 0
        chunks, origins, position = [], [], 0
        for row in rows:
            offset = cursor['offset'] if row['seq'] == cursor['seq'] else 0
            chunk = row['text'][offset:]
            if chunks:
                position += 1
            origins.append(position)
            chunks.append(chunk)
            position += len(chunk)
        text = ' '.join(chunks)

        def location(position):
            line = max(0, bisect_right(origins, position) - 1)
            row = rows[line]
            offset = position - origins[line]
            if line == 0 and row['seq'] == cursor['seq']:
                offset += cursor['offset']
            return row, dict(seq=row['seq'], offset=offset)

        markers = [m.start() for m in re.finditer('>>', text)]
        # An initial empty speech still reserves number zero.
        if state['next_speech'] > 0 and markers and markers[0] == 0:
            markers = markers[1:]
        boundaries = [0] + markers + [len(text)]
        written = 0
        final = event['status'] == -1 and source == 'archive'
        base = None
        if event['recording_start'] is not None and event['preroll_s'] is not None:
            base = datetime.fromisoformat(event['recording_start']) - timedelta(seconds=event['preroll_s'])
        title = (f"House of Commons, sitting {event['number']}" if event['kind'] == 'house'
                 else f"{event['committee']}, meeting {event['number']}")
        for part, (start, end) in enumerate(zip(boundaries, boundaries[1:])):
            is_tail = part == len(boundaries) - 2
            if is_tail and not final:
                break
            if is_tail:
                state['finalized'] = dict(state={field: state[field] for field in STATE_FIELDS},
                                          span_count=len(state['speeches']), last_seq=rows[-1]['seq'])
            speech = text[start:end]
            name = label(speech)
            guess = None
            if name in PRESIDING:
                state['pending'] = index.call(speech, committee=event['kind'] == 'committee')
                state['current'] = None
                speaker = name
            else:
                guess = state['pending'] or state['current'] if name else state['pending']
                if name is None and speech.strip():
                    state['current'] = guess
                    state['pending'] = None
                speaker = index.members[guess[0]] if guess else None
            intervention = f"c{event_id}_{state['next_speech']}"
            pieces = list(_paragraphs(speech))
            if pieces:
                first_row, _ = location(start + pieces[0][0])
                end_row, _ = location(end) if not is_tail else (rows[-1], None)
                state['speeches'].append(dict(id=intervention, begin=first_row['begin'],
                                              end=end_row['end'] if is_tail else end_row['begin'],
                                              how=guess[2] if guess else None))
            for local, paragraph in pieces:
                row, _ = location(start + local)
                at = row['begin']
                offset_s = round((datetime.fromisoformat(at) - base).total_seconds(), 3) if base is not None else None
                number = state['next_position']
                db.execute('INSERT INTO paragraphs(id,document,intervention,position,at,title,lang,text_en,text_fr,'
                           'speaker,person_id,source,event_id,offset_s,confidence) '
                           "VALUES (?,?,?,?,?,?,'en',?,'',?,?,'captions',?,?,?)",
                           (f'c{event_id}_{number}', 'captions/' + event_id, intervention, number, at, title,
                            paragraph, speaker, guess[0] if guess else None, event_id, offset_s, guess[1] if guess else None))
                state['next_position'] += 1
                written += 1
            state['next_speech'] += 1
            if is_tail:
                state['cursor'] = dict(seq=rows[-1]['seq'] + 1, offset=0)
            else:
                _, state['cursor'] = location(end)
        set_meta(db, key, json.dumps(state))
    return written


def segment_all(db, index):
    events = db.execute("SELECT id FROM events WHERE captions IN ('live','archive') "
                        'AND NOT EXISTS (SELECT 1 FROM documents WHERE documents.id=events.document) ORDER BY id').fetchall()
    return sum(segment_event(db, row['id'], index) for row in events)
