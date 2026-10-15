"""Cached Nominatim lookups, including negative results."""

from datetime import datetime, timedelta, timezone
import json
import re
from urllib.parse import urlencode

from watch.ingest import USER_AGENT  # The injected production fetch sends this agent.
from watch.pm.zones import PROVINCES, zone_for
from watch.store import iso


def place_id(heading):
    return re.sub(r'[\W_]+', '-', heading.lower(), flags=re.UNICODE).strip('-')


def lookup(db, heading, fetch, sleep):
    heading = ' '.join(heading.split())
    key, now = place_id(heading), datetime.now(timezone.utc)
    row = db.execute('SELECT * FROM pm_places WHERE id=?', (key,)).fetchone()
    if row and (row['lat'] is not None or
                datetime.fromisoformat(row['looked_up_at']) > now - timedelta(days=30)):
        return row
    region = heading.rsplit(',', 1)[-1].strip()
    country = 'Canada' if region in PROVINCES or heading == 'National Capital Region, Canada' else region
    lat = lon = None
    if heading == 'National Capital Region, Canada':
        lat, lon = 45.4215, -75.6972
    else:
        sleep(1.0)
        try:
            values = json.loads(fetch('https://nominatim.openstreetmap.org/search?' +
                                      urlencode(dict(format='json', limit=1, q=heading))))
            if values:
                lat, lon = float(values[0]['lat']), float(values[0]['lon'])
        except Exception:
            # A failed lookup is cached too, and may be retried after thirty days.
            pass
    db.execute('INSERT INTO pm_places VALUES (?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET '
               'lat=excluded.lat,lon=excluded.lon,zone=excluded.zone,looked_up_at=excluded.looked_up_at',
               (key, heading, country, lat, lon, zone_for(heading, lat, lon), iso(now)))
    return db.execute('SELECT * FROM pm_places WHERE id=?', (key,)).fetchone()
