"""Detect the live alerts: a followed bill's vote being called, its result, and a followed MP speaking."""

import argparse
from bisect import bisect_right
from datetime import datetime, timedelta, timezone
import json
import re
import sqlite3
import sys

from watch import store
from watch.speaker import PRESIDING, CallIndex, label


BILL = re.compile(r'(?<![A-Za-z0-9])([CS])-(\d+)(?![A-Za-z0-9])', re.I)
CALL = re.compile(
    r'\bcall\s+in\s+the\s+members\b'
    r'|\b(?:ten|10)[- ]minute period for (?:members )?(?:voting electronically|electronic voting) '
    r'has (?:now )?start(?:ed)?\b'
    r'|\b(?:the )?electronic voting has (?:now )?started\b'
    r'|\b(?:the )?house will now wait for the electronic voting period to end\b'
    r'|\[\s*calling of recorded vote\s*\]', re.I)
QUESTION = re.compile(
    r'\b(?:the )?(?:(?:first|next) )?question is (?:as follows|on|that|the following|motion)\b'
    r'|\bdeferred recorded division on\b'
    r'|\bmove[sd]? (?:that )?(?=bill\b|the house\b|this question\b)'
    r'|\b(?:second|third) reading of bill\b', re.I)
PROCEDURAL = re.compile(
    r'\bstands deferred\b|\btime[- ]allocation\b|\bclosure\b'
    r'|\b(?:the|this) house (?:do )?(?:now )?adjourn\b'
    r'|\b(?:this|the) question be now put\b'
    r'|\bdebate not be further adjourned\b'
    r'|\bbe disposed of[f]? as follows\b'
    r'|\b(?:hours?|sitting days?) shall be (?:allocated|allotted)\b'
    r'|\bgovernment business (?:no\.?|number)\s*\d+', re.I)
QUESTION_BILL = re.compile(r'\bbill\s+([CS])(?:\s*-\s*|\s+minus\s+|\s*)(\d+)\b', re.I)
VOTE_FRESH = timedelta(minutes=10)
BILL_LOOKBACK = timedelta(minutes=5)
VOTE_CLUSTER = timedelta(minutes=15)
SPEAKING_FRESH = timedelta(minutes=10)
SPEAKING_WINDOW = timedelta(minutes=15)
DIVISION_FRESH = timedelta(hours=24)
MIN_CONFIDENCE = 0.75
RESULT_LEAD = timedelta(minutes=30)
RESULT_LAG = timedelta(minutes=90)


def bill_numbers(text):
    return [f'{m[1]}-{m[2]}'.upper() for m in BILL.finditer(text)]


def _time(text):
    return datetime.fromisoformat(text)


def _stamp(moment):
    """Caption timestamps are fixed-width, so string bounds compare like times."""
    return moment.astimezone(timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.%f')[:-3] + 'Z'


def _lines(db, event_id, source, since, until):
    return db.execute("SELECT seq,begin,text FROM captions WHERE event=? AND lang='en' AND source=? "
                      'AND begin>=? AND begin<=? ORDER BY seq',
                      (event_id, source, _stamp(since), _stamp(until))).fetchall()


def _events(db, kinds, source, now, fresh):
    """Events that can have something new; live captions skip stale events cheaply."""
    marks = ','.join('?' * len(kinds))
    for event in db.execute(f'SELECT * FROM events WHERE kind IN ({marks}) ORDER BY id', kinds).fetchall():
        if source == 'live':
            last = db.execute("SELECT begin FROM captions WHERE event=? AND lang='en' AND source=? "
                              'ORDER BY seq DESC LIMIT 1', (event['id'], source)).fetchone()
            if last is None or _time(last['begin']) < now - fresh:
                continue
        yield event


def _video(event, begin, source):
    offset = None
    if event['recording_start'] is not None and event['preroll_s'] is not None:
        base = _time(event['recording_start']) - timedelta(seconds=event['preroll_s'])
        offset = round((_time(begin) - base).total_seconds(), 3)
    return {'event': event['id'], 'offset_s': offset, 'live': source == 'live'}


def _title(event):
    return (f"House of Commons, sitting {event['number']}" if event['kind'] == 'house'
            else f"{event['committee']}, meeting {event['number']}")


def _bill_follows(follows):
    result = {}
    for follow in follows:
        if follow.get('kind') == 'bill':
            result.setdefault(str(follow['bill']['number']).upper(), []).append(follow)
    return result


def _calls(lines):
    """Triggers ending on this caption, including phrases split across caption lines."""
    for i, line in enumerate(lines):
        if not re.search(r'\b(?:members|started|start|end)\b|\]', line['text'], re.I):
            continue
        previous = ' '.join(row['text'] for row in lines[max(0, i - 7):i])
        joined = previous + ' ' + line['text'] if previous else line['text']
        boundary = len(previous) + 1 if previous else 0
        for match in CALL.finditer(joined):
            if match.end() > boundary:
                yield i, line['text'][:match.end() - boundary]


def _question_bills(lines, i, upto):
    begin = _time(lines[i]['begin'])
    j = i
    while j > 0 and begin - _time(lines[j - 1]['begin']) <= BILL_LOOKBACK:
        j -= 1
    text = ' '.join([row['text'] for row in lines[j:i]] + [upto])
    text = ' '.join(text.split())
    questions = list(QUESTION.finditer(text))
    if not questions:
        return []
    question = text[questions[-1].start():]
    if PROCEDURAL.search(question):
        return []
    # Require the number in the motion itself, before the invitation to request a vote.
    question = re.split(r'\bif (?:a|any) member\b', question, maxsplit=1, flags=re.I)[0]
    numbers = bill_numbers(question)
    numbers += [f'{m[1].upper()}-{m[2]}' for m in QUESTION_BILL.finditer(question)]
    return list(dict.fromkeys(numbers))


def detect_votes(db, now, follows, source='live'):
    wanted = _bill_follows(follows)
    created = []
    if not wanted:
        return created
    for event in _events(db, ('house',), source, now, VOTE_FRESH):
        lines = _lines(db, event['id'], source, now - VOTE_FRESH - VOTE_CLUSTER - BILL_LOOKBACK, now)
        anchors = {}
        for i, upto in _calls(lines):
            begin = _time(lines[i]['begin'])
            for number in _question_bills(lines, i, upto):
                if number in anchors and begin - anchors[number] <= VOTE_CLUSTER:
                    continue
                anchors[number] = begin
                if begin < now - VOTE_FRESH or begin > now:
                    continue
                for follow in wanted.get(number, []):
                    # Persist the cluster across polls, restarts and overlapping replay windows.
                    prior = db.execute(
                        "SELECT 1 FROM alerts WHERE substr(dedupe,1,?)=? AND at>=? AND at<=? LIMIT 1",
                        (len(f"bill_vote:{follow['id']}:{event['id']}:"),
                         f"bill_vote:{follow['id']}:{event['id']}:", _stamp(begin - VOTE_CLUSTER),
                         lines[i]['begin'])).fetchone()
                    if prior:
                        continue
                    alert = dict(at=lines[i]['begin'], kind='bill_vote', follow=follow['id'],
                                 title=f'Vote called on Bill {number}', body='Members are being called in for the vote.',
                                 video=_video(event, lines[i]['begin'], source), division=None)
                    alert_id = store.add_alert(db, alert, f"bill_vote:{follow['id']}:{event['id']}:{lines[i]['seq']}")
                    if alert_id:
                        created.append(alert_id)
    return created


def detect_divisions(db, now, follows):
    wanted = _bill_follows(follows)
    created = []
    for row in db.execute('SELECT * FROM divisions WHERE bill IS NOT NULL AND bill<>? AND at>=? ORDER BY at',
                          ('', store.iso(now - DIVISION_FRESH - timedelta(days=1)))).fetchall():
        if _time(row['at']) < now - DIVISION_FRESH:
            continue
        number = row['bill'].rsplit('/', 1)[-1].upper()
        for follow in wanted.get(number, []):
            division = {key: row[key] for key in ('id', 'number', 'bill', 'description', 'result', 'yeas', 'nays', 'paired')}
            alert = dict(at=row['at'], kind='bill_vote', follow=follow['id'],
                         title=f"Vote on Bill {number}: {row['result']}",
                         body=f"Yeas {row['yeas']}, nays {row['nays']}.", video=None, division=division)
            alert_id = store.add_alert(db, alert, f"division:{follow['id']}:{row['id']}")
            if alert_id:
                created.append(alert_id)
    return created


def detect_speaking(db, now, follows, index, source='live'):
    wanted = {}
    for follow in follows:
        if follow.get('kind') == 'mp':
            wanted.setdefault(str(follow['mp']['person_id']), []).append(follow)
    created = []
    if not wanted:
        return created
    for event in _events(db, ('house', 'committee'), source, now, SPEAKING_FRESH):
        lines = _lines(db, event['id'], source, now - SPEAKING_WINDOW, now)
        if not lines:
            continue
        origins, position = [], 0
        for line in lines:
            origins.append(position)
            position += len(line['text']) + 1
        text = ' '.join(line['text'] for line in lines)
        markers = [m.start() for m in re.finditer('>>', text)]
        boundaries = [0] + markers
        for start, end in zip(boundaries, markers):
            speech = text[start:end]
            if label(speech) not in PRESIDING:
                continue
            called = index.call(speech, committee=event['kind'] == 'committee')
            if called is None or called[1] < MIN_CONFIDENCE or called[0] not in wanted:
                continue
            line = lines[bisect_right(origins, end) - 1]
            if _time(line['begin']) < now - SPEAKING_FRESH:
                continue
            for follow in wanted[called[0]]:
                alert = dict(at=line['begin'], kind='mp_speaking', follow=follow['id'],
                             title=f"{follow['mp']['name']} is speaking",
                             body=f'{_title(event)} - named by the Speaker ({called[2]})',
                             video=_video(event, line['begin'], source), division=None)
                alert_id = store.add_alert(db, alert, f"mp_speaking:{follow['id']}:{event['id']}:{line['seq']}")
                if alert_id:
                    created.append(alert_id)
    return created


def run(data_dir, now):
    with store.connect(data_dir) as db:
        follows = store.list_follows(db)['follows']
        index = CallIndex(db.execute('SELECT * FROM members'), db.execute('SELECT * FROM ministries'))
        created, failures = [], []
        for detector in (lambda: detect_votes(db, now, follows, source='live'),
                         lambda: detect_divisions(db, now, follows),
                         lambda: detect_speaking(db, now, follows, index, source='live')):
            try:
                created += detector()
                db.commit()
            except Exception as exc:
                db.rollback()
                failures.append(str(exc) or type(exc).__name__)
        error = '; '.join(failures) or None
        store.set_meta(db, 'source:alerts', json.dumps({'at': store.iso(now), 'ok': error is None, 'error': error}))
        db.commit()
    return created


def replay(db, event_id, follows, index, step_s=60):
    event_id = str(event_id)
    bounds = db.execute("SELECT min(begin) AS first, max(begin) AS last FROM captions "
                        "WHERE event=? AND lang='en' AND source='archive'", (event_id,)).fetchone()
    if bounds['first'] is None:
        return []
    first, last = _time(bounds['first']), _time(bounds['last'])
    created, now = [], first
    while True:
        now = min(now, last)
        created += detect_votes(db, now, follows, source='archive')
        created += detect_speaking(db, now, follows, index, source='archive')
        if now >= last:
            break
        now += timedelta(seconds=step_s)
    marks = ','.join('?' * len(created))
    rows = db.execute(f'SELECT * FROM alerts WHERE id IN ({marks}) ORDER BY at, id', created).fetchall()
    return [store.alert_dict(row) for row in rows]


def _context(db, event_id, since, until):
    rows = db.execute("SELECT text FROM captions WHERE event=? AND lang='en' AND source='archive' "
                      'AND begin>=? AND begin<=? ORDER BY seq', (event_id, _stamp(since), _stamp(until))).fetchall()
    return ' '.join(row['text'] for row in rows)[-2500:]


def measure(source_db_path, limit=None):
    source = sqlite3.connect('file:' + str(source_db_path) + '?mode=ro', uri=True)
    source.row_factory = sqlite3.Row
    try:
        sql = ("SELECT e.id FROM events e WHERE e.kind='house' AND EXISTS (SELECT 1 FROM captions c WHERE c.event=e.id "
               "AND c.lang='en' AND c.source='archive') ORDER BY e.scheduled_start DESC, e.id DESC")
        ids = [row['id'] for row in source.execute(sql)]
        if limit is not None:
            ids = ids[:limit]
        shared = {table: source.execute(f'SELECT * FROM {table}').fetchall()
                  for table in ('members', 'ministries', 'divisions', 'bills')}
        numbers = sorted({row['bill'].rsplit('/', 1)[-1].upper() for row in shared['divisions'] if row['bill']})
        follows = [{'kind': 'bill', 'id': 'f_' + number, 'label': number, 'bill': {'id': number, 'number': number, 'title': ''}}
                   for number in numbers]
        result = dict(events=0, called=0, matched=0, divisions_in_window=0, recall=None, precision=None,
                      misses=[], false_alerts=[])
        matched_divisions = set()
        for event_id in ids:
            scratch = sqlite3.connect(':memory:')
            scratch.row_factory = sqlite3.Row
            scratch.executescript(store.SCHEMA)
            for table, rows in shared.items():
                if rows:
                    scratch.executemany(f"INSERT INTO {table} VALUES ({','.join('?' * len(rows[0]))})", [tuple(r) for r in rows])
            event = source.execute('SELECT * FROM events WHERE id=?', (event_id,)).fetchone()
            scratch.execute(f"INSERT INTO events VALUES ({','.join('?' * len(event))})", tuple(event))
            scratch.executemany('INSERT INTO captions VALUES (?,?,?,?,?,?,?)', [tuple(r) for r in source.execute(
                "SELECT * FROM captions WHERE event=? AND lang='en' AND source='archive' ORDER BY seq", (event_id,))])
            scratch.execute('CREATE INDEX captions_begin ON captions (event, lang, source, begin)')
            index = CallIndex(scratch.execute('SELECT * FROM members'), scratch.execute('SELECT * FROM ministries'))
            alerts = [a for a in replay(scratch, event_id, follows, index) if a['kind'] == 'bill_vote']
            span = scratch.execute("SELECT min(begin) AS first, max(begin) AS last FROM captions WHERE event=?",
                                   (event_id,)).fetchone()
            first, last = _time(span['first']), _time(span['last'])
            window = [d for d in shared['divisions'] if d['bill'] and first <= _time(d['at']) <= last]
            result['events'] += 1
            result['called'] += len(alerts)
            result['divisions_in_window'] += len(window)
            event_matched = set()
            for alert in alerts:
                at = _time(alert['at'])
                number = alert['title'].rsplit(' ', 1)[-1]
                hits = sorted((d for d in window if d['bill'].rsplit('/', 1)[-1].upper() == number
                               and -RESULT_LEAD <= _time(d['at']) - at <= RESULT_LAG), key=lambda d: d['at'])
                if hits:
                    result['matched'] += 1
                    event_matched.update(d['id'] for d in hits)
                else:
                    result['false_alerts'].append(dict(event=event_id, at=alert['at'], title=alert['title'],
                                                       context=_context(scratch, event_id, at - timedelta(minutes=5), at + timedelta(minutes=1))))
            matched_divisions |= {(event_id, d) for d in event_matched}
            for d in window:
                if d['id'] not in event_matched:
                    at = _time(d['at'])
                    result['misses'].append(dict(event=event_id, division=d['id'], bill=d['bill'], at=d['at'],
                                                 context=_context(scratch, event_id, at - timedelta(minutes=5), at + timedelta(minutes=1))))
            scratch.close()
        result['recall'] = len(matched_divisions) / result['divisions_in_window'] if result['divisions_in_window'] else None
        result['precision'] = result['matched'] / result['called'] if result['called'] else None
        return result
    finally:
        source.close()


def main(argv=None):
    parser = argparse.ArgumentParser(description='Detect Parliament watch alerts')
    commands = parser.add_subparsers(dest='command', required=True)
    commands.add_parser('run').add_argument('--data', default=store.DEFAULT_DATA)
    check = commands.add_parser('measure')
    check.add_argument('--db', required=True)
    check.add_argument('--limit', type=int)
    args = parser.parse_args(argv)
    if args.command == 'run':
        print(json.dumps(run(args.data, datetime.now(timezone.utc))))
    else:
        print(json.dumps(measure(args.db, args.limit), indent=2))
    return 0


if __name__ == '__main__':
    sys.exit(main())
