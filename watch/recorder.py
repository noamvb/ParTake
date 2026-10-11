"""Record English in-band HLS captions as committed SQLite caption lines."""

import argparse
from datetime import datetime, timedelta, timezone
import json
import sys
import time
from urllib.parse import urljoin

from watch.cea608 import Decoder, extract_cc_pairs
from watch.store import DEFAULT_DATA, connect, iso, set_meta


class Lines:
    """Keep visible rows pending until they leave the caption display."""

    def __init__(self):
        self.pending = []

    def change(self, pts, text):
        rows = [row.strip() for row in text.split('\n') if row.strip()] if text is not None else []
        matched = set()
        begins = {}
        committed = []
        for index, (old, begin) in enumerate(self.pending):
            match = next((i for i, row in enumerate(rows) if row == old and i not in matched), None)
            if match is None and index == len(self.pending) - 1 and rows:
                last = len(rows) - 1
                if last not in matched and rows[last].startswith(old):
                    match = last
            if match is None:
                committed.append((old, begin, pts))
            else:
                matched.add(match)
                begins[match] = begin
        self.pending = [(row, begins.get(i, pts)) for i, row in enumerate(rows)]
        return committed

    def flush(self, pts):
        committed = [(text, begin, pts) for text, begin in self.pending]
        self.pending = []
        return committed


def unwrap(pts, previous):
    """Lift a 33-bit PTS to the previous epoch, detecting the half-range wrap."""
    if previous is None:
        return pts
    value = pts + (previous // (1 << 33)) * (1 << 33)
    if previous - value > (1 << 32):
        value += 1 << 33
    return value


def _stamp(value):
    return value.astimezone(timezone.utc).isoformat(timespec='milliseconds').replace('+00:00', 'Z')


def _playlist(body, url):
    """Parse media segment sequence, duration and optional wall-clock time."""
    sequence = 0
    duration = None
    program_time = None
    target = 5
    ended = False
    segments = []
    for line in body.decode('utf-8').splitlines():
        line = line.strip()
        if line.startswith('#EXT-X-MEDIA-SEQUENCE:'):
            sequence = int(line.split(':', 1)[1])
        elif line.startswith('#EXT-X-TARGETDURATION:'):
            target = float(line.split(':', 1)[1])
        elif line.startswith('#EXTINF:'):
            duration = float(line.split(':', 1)[1].split(',', 1)[0])
        elif line.startswith('#EXT-X-PROGRAM-DATE-TIME:'):
            program_time = datetime.fromisoformat(line.split(':', 1)[1])
        elif line == '#EXT-X-ENDLIST':
            ended = True
        elif line and not line.startswith('#') and duration is not None:
            segments.append((sequence, urljoin(url, line), duration, program_time))
            sequence += 1
            # HLS program time applies forward to the following segments too.
            if program_time is not None:
                program_time += timedelta(seconds=duration)
            duration = None
    return segments, target, ended


def _variant(body, url):
    waiting = False
    for line in body.decode('utf-8').splitlines():
        line = line.strip()
        if waiting and line and not line.startswith('#'):
            return urljoin(url, line)
        if line.startswith('#EXT-X-STREAM-INF:'):
            waiting = True
    raise ValueError('master playlist has no variant')


def record(data_dir, event_id, fetch, sleep, now, idle_s=600, max_loops=None):
    """Poll an event's HLS stream; all I/O and time sources are injectable."""
    key = 'recorder:' + str(event_id)
    with connect(data_dir) as db:
        event = db.execute('SELECT * FROM events WHERE id=?', (event_id,)).fetchone()
        if event is None or event['stream_url'] is None:
            return 2
        saved = db.execute('SELECT value FROM meta WHERE key=?', (key,)).fetchone()
        meta = json.loads(saved[0]) if saved else {}
        last_sequence = meta.get('last_sequence', -1)
        anchor = meta.get('anchor')
        seq = db.execute("SELECT coalesce(max(seq)+1,0) FROM captions "
                         "WHERE event=? AND lang='en' AND source='live'", (event_id,)).fetchone()[0]
        decoder = Decoder()
        lines = Lines()
        written = 0
        last_pts = None
        anchors = [anchor] if anchor else []
        target = 5

        def get(url):
            for attempt in range(4):
                try:
                    return fetch(url)
                except Exception as exc:
                    sys.stderr.write('recorder %s: fetch %s: %s\n' % (event_id, url, exc))
                    if attempt == 3:
                        return None
                    sleep(target / 2)

        def wall(pts, vod_base):
            if vod_base is not None:
                return _stamp(vod_base + timedelta(seconds=pts / 90000))
            # Keep previous segment anchors for rows that span a PDT update.
            selected = anchors[0]
            for candidate in anchors:
                if candidate['pts'] <= pts:
                    selected = candidate
            return _stamp(datetime.fromisoformat(selected['wall']) +
                          timedelta(seconds=(pts - selected['pts']) / 90000))

        def write(committed, sequence, vod_base):
            nonlocal seq, written
            with db:
                for text, begin, end in committed:
                    text = text.strip()
                    if not text:
                        continue
                    db.execute("INSERT INTO captions(event,lang,source,seq,begin,end,text) "
                               "VALUES (?,'en','live',?,?,?,?)",
                               (event_id, seq, wall(begin, vod_base), wall(end, vod_base), text))
                    seq += 1
                    written += 1
                    if written == 1:
                        db.execute("UPDATE events SET captions='live' WHERE id=? AND captions='none'", (event_id,))
                set_meta(db, key, json.dumps({'last_sequence': sequence, 'anchor': anchor,
                                              'at': iso(now()), 'lines': written}))

        master = get(event['stream_url'])
        if master is None:
            return 1
        try:
            media_url = _variant(master, event['stream_url'])
        except (ValueError, UnicodeError) as exc:
            sys.stderr.write('recorder %s: %s\n' % (event_id, exc))
            return 1
        loops = 0
        last_new = now()
        vod_base = None
        while max_loops is None or loops < max_loops:
            body = get(media_url)
            if body is None:
                return 1
            fetch_time = now()
            loops += 1
            try:
                segments, target, ended = _playlist(body, media_url)
            except (ValueError, UnicodeError) as exc:
                sys.stderr.write('recorder %s: invalid media playlist: %s\n' % (event_id, exc))
                return 1
            vod_base = None
            if ended and event['recording_start'] is not None and event['preroll_s'] is not None:
                vod_base = datetime.fromisoformat(event['recording_start']) - timedelta(seconds=event['preroll_s'])
            for index, (sequence, url, duration, program_time) in enumerate(segments):
                if sequence <= last_sequence:
                    continue
                segment = get(url)
                if segment is None:
                    return 1
                last_new = now()
                committed = []
                try:
                    pairs = extract_cc_pairs(segment)
                    if pairs:
                        first_pts = unwrap(pairs[0][0], last_pts)
                        if vod_base is None:
                            if program_time is not None:
                                current = {'pts': first_pts, 'wall': _stamp(program_time)}
                                anchors.append(current)
                                anchor = current
                            elif anchor is None:
                                remaining = sum(item[2] for item in segments[index:])
                                anchor = {'pts': first_pts, 'wall': _stamp(fetch_time - timedelta(seconds=remaining))}
                                anchors.append(anchor)
                        for pts, b1, b2, field in pairs:
                            last_pts = unwrap(pts, last_pts)
                            if field != 0:
                                continue
                            change = decoder.push(last_pts, b1, b2)
                            if change is not None:
                                committed.extend(lines.change(*change))
                    else:
                        sys.stderr.write('recorder %s: segment %s has no caption pairs\n' % (event_id, sequence))
                except Exception as exc:
                    sys.stderr.write('recorder %s: undecodable segment %s: %s\n' % (event_id, sequence, exc))
                last_sequence = sequence
                write(committed, last_sequence, vod_base)
            if ended or (now() - last_new).total_seconds() >= idle_s or (max_loops is not None and loops >= max_loops):
                write(lines.flush(last_pts), last_sequence, vod_base)
                return 0
            sleep(target / 2)
        return 0


def main(argv=None):
    from watch.ingest import fetch

    parser = argparse.ArgumentParser(description='Record Parliament watch live English captions')
    parser.add_argument('--data', default=DEFAULT_DATA)
    parser.add_argument('--event', required=True)
    args = parser.parse_args(argv)
    return record(args.data, args.event, fetch, time.sleep, lambda: datetime.now(timezone.utc))


if __name__ == '__main__':
    sys.exit(main())
