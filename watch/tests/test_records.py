from collections import Counter
import gzip
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

from watch import records
from watch.ingest import parse_members, parse_ministries


FIXTURES = Path(__file__).parent / 'fixtures'


def fixture(name):
    body = (FIXTURES / name).read_bytes()
    return gzip.decompress(body) if name.endswith('.gz') else body


class RecordsTests(unittest.TestCase):
    def transcript(self, evidence=False):
        from watch.records import parse_transcript
        stem = 'INDUEV50' if evidence else 'HAN149'
        return parse_transcript(fixture(stem + '-E.XML.gz'), fixture(stem + '-F.XML.gz'),
                                source='evidence' if evidence else 'hansard',
                                number=50 if evidence else 149, committee='INDU' if evidence else None)

    def index(self):
        from watch.records import SpeakerIndex
        return SpeakerIndex(parse_members(fixture('members.xml.gz')),
                            parse_ministries(fixture('ministries.xml.gz')))

    def test_01_hansard(self):
        doc, rows = self.transcript()
        self.assertEqual(len(rows), 677)
        self.assertEqual(Counter(p['lang'] for p in rows), {'en': 438, 'fr': 239})
        self.assertEqual(doc, {'id': 'hansard/45-1/149', 'source': 'hansard', 'session': '45-1',
                              'number': 149, 'committee': None, 'date': '2026-10-09',
                              'url': 'https://www.ourcommons.ca/DocumentViewer/en/45-1/house/sitting-149/hansard'})
        self.assertTrue(all(p['position'] == i for i, p in enumerate(rows)))

    def test_02_hansard_paragraph(self):
        p = next(p for p in self.transcript()[1] if p['id'] == 'h9484631')
        self.assertEqual((p['intervention'], p['lang'], p['at'], p['title'], p['speaker'], p['db_id']),
                         ('13631467', 'en', '2026-10-09T14:00:00Z', 'Government Orders - First Nations Clean Water Act',
                          'Hon. Mandy Gull-Masty (Minister of Indigenous Services, Lib.)', '318665'))
        self.assertEqual(p['text_en'], 'She said: Madam Speaker, waachiyeh, meesuuyeh, kwe, ulaakut, tansi and hello. I rise today as a proud eeyou iskwew from the community of Waswanipi, and also as the Minister of Indigenous Services, to speak to Bill C-37, the first nations clean water act.')

    def test_03_translation(self):
        p = next(p for p in self.transcript()[1] if p['id'] == 'h9484633')
        self.assertEqual(p['lang'], 'fr')
        self.assertTrue(p['text_fr'].startswith("Ces moments m'ont appris très tôt que l'eau est bien plus qu'une ressource"))
        self.assertTrue(p['text_en'].startswith('From that, I learned very early on'))

    def test_04_evidence(self):
        doc, rows = self.transcript(True)
        self.assertEqual((doc['id'], doc['date']), ('evidence/45-1/INDU/50', '2026-10-06'))
        self.assertEqual(len(rows), 200)
        self.assertEqual(Counter(p['lang'] for p in rows), {'en': 95, 'fr': 105})
        p = next(p for p in rows if p['id'] == 'e9484374')
        self.assertEqual((p['title'], p['at'], p['lang']), ('INDU, meeting 50', '2026-10-06T15:05:00Z', 'fr'))
        self.assertTrue(p['text_fr'].startswith('Comme vous le savez, le CRTC'))

    def test_05_hansard_speakers(self):
        index, cache = self.index(), {}
        rows = {p['intervention']: p for p in self.transcript()[1]}
        self.assertEqual(len(rows), 211)
        self.assertTrue(all(index.resolve(p['speaker'], p['db_id'], cache) for p in rows.values()))
        for text, pid in [('Billy Morin (Edmonton Northwest, CPC)', '123447'), ('Prime Minister', '28286'),
                          ('The Assistant Deputy Speaker (Alexandra Mendès)', '58621'),
                          ('Hon. Mandy Gull-Masty (Minister of Indigenous Services, Lib.)', '122492')]:
            self.assertEqual(index.resolve(text, None, {}), pid)

    def test_06_evidence_speakers(self):
        index, cache = self.index(), {}
        rows = {p['intervention']: p for p in self.transcript(True)[1]}
        resolved = {key: index.resolve(p['speaker'], p['db_id'], cache) for key, p in rows.items()}
        self.assertEqual(Counter(bool(v) for v in resolved.values()), {True: 39, False: 24})
        root = ET.fromstring(fixture('INDUEV50-E.XML.gz'))
        types = {i.get('id'): i.find('PersonSpeaking/Affiliation').get('Type') for i in root.iter('Intervention')}
        self.assertTrue(all(types[key] == '28' for key, value in resolved.items() if value is None))
        self.assertEqual(index.resolve('Ms. Dandurand', None, {}), '122559')
        self.assertEqual(index.resolve('The Chair (Ben Carr (Winnipeg South Centre, Lib.))', None, {}), '115744')

    def test_07_cache(self):
        index, cache = self.index(), {}
        self.assertEqual(index.resolve('Billy Morin', 'test', cache), '123447')
        self.assertEqual(index.resolve('unparseable', 'test', cache), '123447')
        self.assertIsNone(index.resolve('unparseable', 'test', {}))

    def test_08_divisions(self):
        from watch.records import parse_divisions
        rows = parse_divisions(fixture('votes.xml.gz'))
        self.assertEqual(len(rows), 178)
        self.assertEqual(Counter(r['result'] for r in rows), {'agreed': 100, 'negatived': 77, 'tie': 1})
        self.assertEqual(sum(r['bill'] is not None for r in rows), 99)
        r = next(r for r in rows if r['id'] == '45-1/178')
        self.assertEqual((r['at'], r['bill'], r['yeas'], r['nays'], r['paired']),
                         ('2026-10-08T19:15:00Z', '45-1/C-39', 296, 26, 10))

    def test_09_ballots(self):
        from watch.records import parse_ballots
        rows = parse_ballots(fixture('vote-45-1-178.xml.gz'))
        self.assertEqual(len(rows), 332)
        self.assertEqual(Counter(r['vote'] for r in rows), {'yea': 296, 'nay': 26, 'paired': 10})
        self.assertEqual(next(r['vote'] for r in rows if r['person_id'] == '123447'), 'yea')
        self.assertEqual(sum(r['party'] == 'Bloc Québécois' and r['vote'] == 'nay' for r in rows), 20)

    def test_10_bill_stages(self):
        from watch.records import parse_bill_stages
        rows = parse_bill_stages(fixture('legisinfo-bills.json'))
        self.assertEqual(len(rows), 4)
        self.assertEqual({(r['stage'], r['chamber'], r['at']) for r in rows if r['bill'] == '45-1/C-37'},
                         {('First reading', 'house', '2026-06-16T14:02:58Z'), ('Second reading', 'house', '2026-10-09T17:20:48Z')})
        self.assertEqual([(r['stage'], r['chamber'], r['at']) for r in rows if r['bill'] == '45-1/S-1'],
                         [('First reading', 'senate', '2025-05-27T04:00:00Z')])

    def test_11_paratext_without_id_is_skipped(self):
        xml = (b'<Hansard><ExtractedInformation><ExtractedItem Name="MetaDateNumYear">2025</ExtractedItem>'
               b'<ExtractedItem Name="MetaDateNumMonth">5</ExtractedItem><ExtractedItem Name="MetaDateNumDay">29</ExtractedItem>'
               b'</ExtractedInformation><HansardBody><Intervention id="1"><Content><ParaText>\n  </ParaText>'
               b'<ParaText id="7">Text</ParaText></Content></Intervention></HansardBody></Hansard>')
        _document, paragraphs = records.parse_transcript(xml, xml, source="hansard", number=4)
        self.assertEqual([p["id"] for p in paragraphs], ["h7"])

    def test_12_timestamp_past_midnight(self):
        xml = (b'<Hansard><ExtractedInformation><ExtractedItem Name="MetaDateNumYear">2025</ExtractedItem>'
               b'<ExtractedItem Name="MetaDateNumMonth">6</ExtractedItem><ExtractedItem Name="MetaDateNumDay">19</ExtractedItem>'
               b'</ExtractedInformation><HansardBody><Timestamp Hr="24" Mn="5" /><Intervention id="1"><Content>'
               b'<ParaText id="7">Text</ParaText></Content></Intervention></HansardBody></Hansard>')
        _document, paragraphs = records.parse_transcript(xml, xml, source="hansard", number=4)
        self.assertEqual(paragraphs[0]["at"], "2025-06-20T04:05:00Z")
