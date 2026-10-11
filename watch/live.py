"""Supervise live ParlVU caption recorders and match their paragraphs."""

import argparse
from datetime import datetime, timezone
import json
import subprocess
import sys
import time

from watch import embed, parlvu, worker
from watch.ingest import fetch as fetch_url, store_raw
from watch.store import DEFAULT_DATA, connect, iso, list_follows, set_meta


class SystemdUnits:
    """Operate recorder user units without a shell."""

    def active(self):
        result = subprocess.run(
            ['systemctl', '--user', 'list-units', 'partake-watch-recorder@*',
             '--state=active', '--plain', '--no-legend'],
            check=True, capture_output=True, text=True)
        active = set()
        prefix = 'partake-watch-recorder@'
        for line in result.stdout.splitlines():
            fields = line.split()
            if not fields:
                continue
            name = fields[0]
            if name.startswith(prefix) and name.endswith('.service'):
                status = subprocess.run(['systemctl', '--user', 'is-active', name],
                                        capture_output=True, text=True)
                if status.returncode == 0:
                    active.add(name[len(prefix):-len('.service')])
        return active

    def start(self, event_id):
        name = 'partake-watch-recorder@' + event_id + '.service'
        subprocess.run(['systemctl', '--user', 'reset-failed', name], check=True,
                       capture_output=True, text=True)
        subprocess.run(['systemctl', '--user', 'start', name], check=True,
                       capture_output=True, text=True)


def tick(data_dir, fetch, now, units, max_recorders=3):
    """Refresh upcoming events and start eligible recorders; never stop one."""
    wanted, started, active, errors = [], [], set(), []
    try:
        active = units.active()
        body = fetch(parlvu.BASE + '/Harmony/en/api/Data/GetUpcomingEvents?lastModified=')
        store_raw(data_dir, 'parlvu', body, now, key='parlvu/upcoming')
        parlvu.save_events(data_dir, parlvu.parse_upcoming(body), now)
        with connect(data_dir) as db:
            committees = {follow['committee']['code'] for follow in list_follows(db)['follows']
                          if follow['kind'] == 'committee'}
            events = [dict(row) for row in db.execute(
                "SELECT * FROM events WHERE status=1 ORDER BY kind != 'house',scheduled_start,id")
                      if row['kind'] == 'house' or
                      (row['kind'] == 'committee' and row['committee'] in committees)]
        events = events[:max(0, max_recorders)]
        wanted = [event['id'] for event in events]
        for event in events:
            event_id = event['id']
            try:
                if event['stream_url'] is None:
                    body = fetch(parlvu.BASE + '/Harmony/en/PowerBrowser/PowerBrowserV2/-1/-1/' + event_id)
                    store_raw(data_dir, 'parlvu_pages', body, now, key='parlvu/event/' + event_id)
                    page = parlvu.parse_event_page(body)
                    with connect(data_dir) as db, db:
                        db.execute('UPDATE events SET recording_start=?,preroll_s=?,stream_url=? WHERE id=?',
                                   (page['recording_start'], page['preroll_s'], page['stream_url'], event_id))
                    event['stream_url'] = page['stream_url']
                if event_id not in active and event['stream_url'] and len(active) < max_recorders:
                    units.start(event_id)
                    started.append(event_id)
                    active.add(event_id)
            except Exception as exc:
                errors.append(event_id + ': ' + (str(exc) or type(exc).__name__))
    except Exception as exc:
        errors.append(str(exc) or type(exc).__name__)
    with connect(data_dir) as db, db:
        set_meta(db, 'source:live', json.dumps({'at': iso(now), 'ok': not errors,
                                              'error': '; '.join(errors) if errors else None}))
    return {'wanted': wanted, 'started': started, 'active': sorted(active)}


def main(argv=None, *, fetch=fetch_url, now=None, units=None, sleep=time.sleep,
         monotonic=time.monotonic, max_ticks=None):
    parser = argparse.ArgumentParser(description='Supervise live Parliament caption recorders')
    parser.add_argument('--data', default=DEFAULT_DATA)
    parser.add_argument('--ollama', default=embed.URL)
    parser.add_argument('--interval', type=float, default=60)
    parser.add_argument('--work-every', type=float, default=120)
    args = parser.parse_args(argv)
    if args.interval <= 0 or args.work_every <= 0:
        parser.error('--interval and --work-every must be positive')
    now = now or (lambda: datetime.now(timezone.utc))
    units = units if units is not None else SystemdUnits()
    last_work = None
    ticks = 0
    while max_ticks is None or ticks < max_ticks:
        result = tick(args.data, fetch, now(), units)
        at = monotonic()
        if result['active'] and (last_work is None or at - last_work >= args.work_every):
            worker.main(['--data', args.data, '--ollama', args.ollama])
            last_work = at
        ticks += 1
        if max_ticks is None or ticks < max_ticks:
            sleep(args.interval)
    return 0


if __name__ == '__main__':
    sys.exit(main())
