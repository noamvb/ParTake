"""PMO RSS polling and resumable live-page history backfill."""

import argparse
from datetime import date, datetime, timedelta, timezone
from email.utils import parsedate_to_datetime
import gzip
import hashlib
from html import escape
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import sys
from time import sleep
from urllib.error import HTTPError
from urllib.parse import urljoin, urlsplit
import xml.etree.ElementTree as ET
from zoneinfo import ZoneInfo

from watch.ingest import fetch
from watch.pm.itinerary import article_body, parse_itinerary
from watch.pm.places import lookup
from watch.store import DEFAULT_DATA, connect, iso, set_meta


BASE = 'https://www.pm.gc.ca'
RSS = BASE + '/en/news.rss'
OTTAWA = ZoneInfo('America/Toronto')
TYPES = {'media-advisories': 'itinerary', 'readouts': 'readout', 'news-releases': 'release',
         'statements': 'statement', 'speeches': 'speech', 'backgrounders': 'backgrounder'}
ALLOWED = {'p', 'h2', 'h3', 'ul', 'ol', 'li', 'strong', 'em', 'a', 'br'}


class _Sanitize(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.html, self.text = [], []
        self.hidden = 0

    def handle_starttag(self, tag, attrs):
        if tag in ('script', 'style', 'iframe', 'object'):
            self.hidden += 1
        if self.hidden or tag not in ALLOWED:
            return
        attr = ''
        if tag == 'a':
            href = dict(attrs).get('href', '')
            if not urlsplit(href).scheme or urlsplit(href).scheme.lower() in ('https', 'http', 'mailto'):
                attr = ' href="%s"' % escape(href, quote=True)
        self.html.append('<%s%s>' % (tag, attr))
        if tag in ('p', 'h2', 'h3', 'li', 'br'):
            self.text.append(' ')

    def handle_endtag(self, tag):
        if tag in ('script', 'style', 'iframe', 'object'):
            self.hidden = max(0, self.hidden - 1)
            return
        if not self.hidden and tag in ALLOWED and tag != 'br':
            self.html.append('</%s>' % tag)
            if tag in ('p', 'h2', 'h3', 'li'):
                self.text.append(' ')

    def handle_data(self, data):
        if not self.hidden:
            data = data.replace('\xa0', ' ')
            self.html.append(escape(data, quote=False))
            self.text.append(data)


def sanitize(body):
    parser = _Sanitize()
    parser.feed(body)
    return ''.join(parser.html), ' '.join(''.join(parser.text).split())


class _Metadata(HTMLParser):
    def __init__(self):
        super().__init__()
        self.values = {}

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == 'meta':
            self.values[attrs.get('property', attrs.get('name'))] = attrs.get('content', '')
        elif tag == 'link' and attrs.get('rel') == 'canonical':
            self.values['canonical'] = attrs.get('href')


def item_id(url):
    path = urlsplit(url).path
    if not path.startswith('/en/news/'):
        raise ValueError('not a PMO news URL')
    return path[len('/en/news/'):].rstrip('/')


def itinerary_date(title):
    match = re.search(r'([A-Z][a-z]+ \d{1,2}, \d{4})', title)
    if not match:
        raise ValueError('itinerary date missing from title')
    return datetime.strptime(match[1], '%B %d, %Y').date().isoformat()


def starts_at(day, local_time, zone):
    if zone is None:
        return None
    return iso(datetime.fromisoformat(day + 'T' + local_time).replace(tzinfo=ZoneInfo(zone)))


def save_item(db, url, title, published_at, body, source, fetch, sleep, now):
    key = item_id(url)
    kind = TYPES.get(key.split('/')[0], 'other')
    previous = db.execute('SELECT published_at FROM pm_items WHERE id=?', (key,)).fetchone()
    if previous and previous[0] > published_at:
        return
    clean, text = sanitize(body)
    db.execute('INSERT INTO pm_items VALUES (?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET '
               'type=excluded.type,title=excluded.title,url=excluded.url,published_at=excluded.published_at,'
               'body_html=excluded.body_html,text=excluded.text,source=excluded.source,fetched_at=excluded.fetched_at',
               (key, kind, title, url, published_at, clean, text, source, iso(now)))
    if kind != 'itinerary':
        return
    day = itinerary_date(title)
    meta_key = 'pm:day:' + day
    winner = db.execute('SELECT value FROM meta WHERE key=?', (meta_key,)).fetchone()
    winner = json.loads(winner[0]) if winner else None
    if winner and (winner['published_at'], winner['item_id']) > (published_at, key):
        return
    parsed = parse_itinerary(body)
    db.execute('DELETE FROM pm_events WHERE date=?', (day,))
    for seq, event in enumerate(parsed['events']):
        place = lookup(db, event['place'], fetch, sleep)
        db.execute('INSERT INTO pm_events VALUES (?,?,?,?,?,?,?,?,?)',
                   (key, day, seq, event['local_time'], starts_at(day, event['local_time'], place['zone']),
                    place['id'], event['text'], event['venue'], event['media']))
    set_meta(db, meta_key, json.dumps(dict(item_id=key, published_at=published_at)))


def _raw(data_dir, key, body, now):
    digest = hashlib.sha256(body).hexdigest()
    with connect(data_dir) as db, db:
        meta_key = 'raw:pm:' + key
        previous = db.execute('SELECT value FROM meta WHERE key=?', (meta_key,)).fetchone()
        if previous and previous[0] == digest:
            return
        at = iso(now)
        path = Path(data_dir).expanduser() / 'raw' / 'pm' / (at[:10] + '.jsonl.gz')
        path.parent.mkdir(parents=True, exist_ok=True)
        with gzip.open(path, 'at', encoding='utf-8') as raw:
            raw.write(json.dumps(dict(at=at, key=key, sha256=digest, body=body.decode('utf-8-sig')),
                                 ensure_ascii=False) + '\n')
        set_meta(db, meta_key, digest)


def _status(data_dir, now, error=None):
    with connect(data_dir) as db, db:
        set_meta(db, 'source:pm', json.dumps(dict(at=iso(now), ok=error is None, error=error)))
        if error is None:
            set_meta(db, 'pm:fetched_at', iso(now))
    return error is None


def poll_pm(data_dir, fetch, sleep, now) -> bool:
    try:
        payload = fetch(RSS)
        _raw(data_dir, 'rss', payload, now)
        items = ET.fromstring(payload).findall('./channel/item')
        if not items:
            raise ValueError('empty PMO RSS')
        with connect(data_dir) as db, db:
            for item in items:
                save_item(db, item.findtext('link'), item.findtext('title'),
                          iso(parsedate_to_datetime(item.findtext('pubDate'))),
                          item.findtext('description') or '', 'rss', fetch, sleep, now)
        return _status(data_dir, now)
    except Exception as exc:
        return _status(data_dir, now, str(exc) or type(exc).__name__)


def _page(data_dir, url, payload, fetch, sleep, now):
    html = payload.decode('utf-8-sig')
    parser = _Metadata()
    parser.feed(html)
    values = parser.values
    canonical = values.get('canonical') or values.get('og:url')
    if '/media-advisories/' in url and canonical and urlsplit(canonical).hostname in ('pm.gc.ca', 'www.pm.gc.ca'):
        url = BASE + urlsplit(canonical).path
    published = values.get('article:published_time')
    if published:
        published = iso(datetime.strptime(published, '%a, %m/%d/%Y - %H:%M').replace(tzinfo=OTTAWA))
    else:
        match = re.search(r'/\d{4}/\d{2}/\d{2}/', url)
        if not match:
            raise ValueError('path date missing')
        day = match[0].strip('/').replace('/', '-')
        published = starts_at(day, '12:00', 'America/Toronto')
    _raw(data_dir, item_id(url), payload, now)
    with connect(data_dir) as db, db:
        save_item(db, url, values['og:title'], published, article_body(html), 'backfill', fetch, sleep, now)


def backfill(data_dir, fetch, sleep, now, since='2025-03-14'):
    since_date = date.fromisoformat(since)
    tomorrow = now.astimezone(OTTAWA).date() + timedelta(days=1)
    requested = False

    def get(url, redirects=0):
        nonlocal requested
        if requested:
            sleep(1.0)
        requested = True
        try:
            return fetch(url)
        except HTTPError as exc:
            if exc.code in (301, 302) and redirects < 5:
                target = urljoin(url, exc.headers['Location'])
                if urlsplit(target).hostname not in ('pm.gc.ca', 'www.pm.gc.ca'):
                    raise ValueError('unexpected PMO redirect') from exc
                return get(target, redirects + 1)
            raise

    def stored(url):
        with connect(data_dir) as db:
            return db.execute('SELECT 1 FROM pm_items WHERE id=?', (item_id(url),)).fetchone() is not None

    day = since_date
    while day <= tomorrow:
        slug = '%s-%s-%d-%d' % (day.strftime('%A').lower(), day.strftime('%B').lower(), day.day, day.year)
        path = BASE + '/en/news/media-advisories/' + (day - timedelta(days=1)).strftime('%Y/%m/%d/')
        for prefix in ('', 'update-'):
            url = path + prefix + slug
            if stored(url):
                continue
            # Redirected canonical ids can have a different path date.
            with connect(data_dir) as db:
                seen = db.execute("SELECT 1 FROM pm_items WHERE type='itinerary' AND id LIKE ?",
                                  ('media-advisories/%/' + prefix + slug,)).fetchone()
            if seen:
                continue
            try:
                payload = get(url)
            except HTTPError as exc:
                if exc.code == 404:
                    continue
                raise
            _page(data_dir, url, payload, fetch, sleep, now)
        day += timedelta(days=1)
    for segment in ('readouts', 'news-releases', 'statements', 'speeches', 'backgrounders'):
        for year in range(2025, now.year + 1):
            cdx = ('https://web.archive.org/cdx/search/cdx?url=pm.gc.ca/en/news/%s/%d/'
                   '&matchType=prefix&fl=original&collapse=urlkey') % (segment, year)
            urls = set()
            for original in fetch(cdx).decode('utf-8-sig').splitlines():
                path = urlsplit(original.strip()).path
                match = re.fullmatch(r'/en/news/' + segment + r'/(\d{4})/(\d{2})/(\d{2})/[a-z0-9]+(?:-[a-z0-9]+)*', path)
                if match and '-'.join(match.groups()) >= since:
                    urls.add(BASE + path)
            for url in sorted(urls):
                if not stored(url):
                    try:
                        payload = get(url)
                    except HTTPError as exc:
                        # The Archive also lists junk URLs that pm.gc.ca rejects (400) or lacks (404).
                        if 400 <= exc.code < 500:
                            continue
                        raise
                    _page(data_dir, url, payload, fetch, sleep, now)
    _status(data_dir, now)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--backfill', action='store_true', required=True)
    parser.add_argument('--data', default=DEFAULT_DATA)
    parser.add_argument('--since', default='2025-03-14')
    args = parser.parse_args(argv)
    try:
        backfill(args.data, fetch, sleep, datetime.now(timezone.utc), args.since)
    except Exception as exc:
        sys.stderr.write(str(exc) + '\n')
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
