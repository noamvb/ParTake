from contextlib import redirect_stderr
from datetime import datetime, timezone
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from urllib.error import HTTPError

from watch.ingest import ingest_source
from watch.store import connect
from watch.tests.test_records import fixture


NOW = datetime(2026, 10, 12, 15, tzinfo=timezone.utc)
HOUSE = 'https://www.ourcommons.ca/Content/House/451/Debates/'
MEETINGS = 'https://api.openparliament.ca/committees/meetings/?format=json&limit=500'
VOTES = 'https://www.ourcommons.ca/Members/en/votes/'


class PollTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.data = Path(self.temp.name)
        self.calls, self.sleeps = [], []

    def fetcher(self, mapping):
        def fetch(url):
            self.calls.append(url)
            if url not in mapping:
                raise HTTPError(url, 404, 'not found', None, None)
            return mapping[url]
        return fetch

    def health(self, source):
        with connect(self.data) as db:
            return json.loads(db.execute('SELECT value FROM meta WHERE key=?', ('source:' + source,)).fetchone()[0])

    def seed(self):
        for source in ('members', 'ministries'):
            self.assertTrue(ingest_source(self.data, source, fetch=lambda url, s=source: fixture(s + '.xml.gz'), now=NOW))
        with connect(self.data) as db, db:
            db.execute("INSERT INTO documents VALUES ('hansard/45-1/148','hansard','45-1',148,NULL,'2026-10-08','url','now')")

    def test_12_hansard_poll(self):
        from watch.poll import poll_hansard
        self.seed()
        urls = [HOUSE + '149/HAN149-' + lang + '.XML' for lang in ('E', 'F')]
        fetch = self.fetcher(dict(zip(urls, [fixture('HAN149-E.XML.gz'), fixture('HAN149-F.XML.gz')])))
        self.assertTrue(poll_hansard(self.data, fetch, self.sleeps.append, NOW))
        self.assertEqual(self.calls, urls + [HOUSE + '150/HAN150-E.XML'])
        with connect(self.data) as db:
            self.assertEqual(tuple(db.execute('SELECT count(*),count(person_id) FROM paragraphs').fetchone()), (677, 677))
            self.assertGreater(db.execute('SELECT count(*) FROM affiliations').fetchone()[0], 0)
        self.assertTrue(self.health('hansard')['ok'])
        self.calls.clear()
        self.assertTrue(poll_hansard(self.data, fetch, self.sleeps.append, NOW))
        self.assertEqual(self.calls, [HOUSE + '150/HAN150-E.XML'])
        with connect(self.data) as db:
            self.assertEqual(db.execute('SELECT count(*) FROM paragraphs').fetchone()[0], 677)

    def test_13_hansard_atomicity(self):
        from watch.poll import poll_hansard
        self.seed()
        with tempfile.TemporaryDirectory() as control:
            good = self.fetcher({HOUSE + '001/HAN001-E.XML': fixture('HAN149-E.XML.gz'),
                                 HOUSE + '001/HAN001-F.XML': fixture('HAN149-F.XML.gz')})
            self.assertTrue(poll_hansard(control, good, self.sleeps.append, NOW, max_docs=1))
            with connect(control) as db:
                self.assertEqual(db.execute('SELECT count(*) FROM documents').fetchone()[0], 1)
                self.assertEqual(db.execute('SELECT count(*) FROM paragraphs').fetchone()[0], 677)
        fetch = self.fetcher({HOUSE + '149/HAN149-E.XML': fixture('HAN149-E.XML.gz'), HOUSE + '149/HAN149-F.XML': b'not xml'})
        self.assertFalse(poll_hansard(self.data, fetch, self.sleeps.append, NOW))
        with connect(self.data) as db:
            self.assertEqual(db.execute('SELECT count(*) FROM documents').fetchone()[0], 1)
            self.assertEqual(db.execute('SELECT count(*) FROM paragraphs').fetchone()[0], 0)
        self.assertFalse(self.health('hansard')['ok'])
        self.assertTrue(self.health('hansard')['error'])

    def test_14_evidence_poll(self):
        from watch.poll import poll_evidence
        import re
        from urllib.parse import urljoin
        self.seed()
        page = 'https://www.ourcommons.ca/DocumentViewer/en/45-1/INDU/meeting-50/evidence'
        html = fixture('INDU-meeting-50-evidence.html.gz')
        xml = urljoin('https://www.ourcommons.ca', re.search(r'href=["\']([^"\']+-E.XML)["\']', html.decode()).group(1))
        committee = 'https://api.openparliament.ca/committees/industry-and-technology/?format=json'
        fetch = self.fetcher({MEETINGS: fixture('op-meetings.json'), committee: fixture('op-committee-industry-and-technology.json'),
                              page: html, xml: fixture('INDUEV50-E.XML.gz'), xml.replace('-E.XML', '-F.XML'): fixture('INDUEV50-F.XML.gz')})
        self.assertTrue(poll_evidence(self.data, fetch, self.sleeps.append, NOW))
        self.assertEqual(self.calls, [MEETINGS, committee, page, xml, xml.replace('-E.XML', '-F.XML')])
        with connect(self.data) as db:
            self.assertEqual(db.execute("SELECT count(*) FROM paragraphs WHERE document='evidence/45-1/INDU/50'").fetchone()[0], 200)
            self.assertEqual(tuple(db.execute('SELECT * FROM committees').fetchone()), ('industry-and-technology', 'INDU'))
        self.calls.clear()
        self.assertTrue(poll_evidence(self.data, fetch, self.sleeps.append, NOW))
        self.assertEqual(self.calls, [MEETINGS])

    def test_15_votes_partial_failure(self):
        from watch.poll import poll_votes
        fetch = self.fetcher({VOTES + 'xml': fixture('votes.xml.gz'), VOTES + '45/1/178/xml': fixture('vote-45-1-178.xml.gz')})
        self.assertFalse(poll_votes(self.data, fetch, self.sleeps.append, NOW))
        with connect(self.data) as db:
            self.assertEqual(db.execute('SELECT count(*) FROM divisions').fetchone()[0], 178)
            self.assertEqual(db.execute("SELECT ballots_loaded FROM divisions WHERE id='45-1/178'").fetchone()[0], 1)
            self.assertEqual(db.execute('SELECT count(*) FROM ballots').fetchone()[0], 332)
        self.assertFalse(self.health('votes')['ok'])
        self.assertTrue(self.sleeps)
        self.assertEqual(self.calls[1], VOTES + '45/1/1/xml')

    def test_17_cli(self):
        from watch.poll import main
        fetch = self.fetcher({VOTES + 'xml': b'<ArrayOfVote/>'})
        output = io.StringIO()
        with patch('watch.poll.fetch', fetch), patch('watch.poll.sleep', self.sleeps.append), redirect_stderr(output):
            self.assertEqual(main(['--data', str(self.data), '--sources', 'votes']), 0)
        self.assertEqual(output.getvalue(), 'votes ok\n')
        output = io.StringIO()
        with patch('watch.poll.fetch', self.fetcher({})), patch('watch.poll.sleep', self.sleeps.append), redirect_stderr(output):
            self.assertEqual(main(['--data', str(self.data), '--sources', 'votes']), 1)
        self.assertEqual(output.getvalue(), 'votes failed\n')
