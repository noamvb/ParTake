from datetime import datetime, timedelta, timezone
import json
import time
import unittest

from watch.records import parse_transcript
from watch.tests.test_records import fixture


def interventions(paragraphs):
    result = {}
    for row in sorted(paragraphs, key=lambda p: p['position']):
        item = result.setdefault(row['intervention'], dict(id=row['intervention'], at=row['at'], text=''))
        item['text'] = (item['text'] + ' ' + row['text_en']).strip()
    return list(result.values())


class AlignTests(unittest.TestCase):
    def test_10_matching(self):
        from watch.align import align
        at = '2026-10-09T14:00:00Z'
        text = 'one two three four five six seven eight'
        lines = [dict(begin='2026-10-09T13:58:59Z', text='outside window has eight words that match now'),
                 dict(begin=at, text=text), dict(begin='2026-10-09T14:01:00Z', text='alpha beta gamma delta epsilon zeta eta theta')]
        speeches = [dict(id='exact', at=at, text=text), dict(id='four', at=at, text='one two three four OTHER WORDS DIFFERENT END'),
                    dict(id='outside', at=at, text=lines[0]['text']), dict(id='later', at=at, text=lines[2]['text']),
                    dict(id='backward', at=at, text=text), dict(id='short', at=at, text='one two three')]
        self.assertEqual(align(speeches, lines), {'exact': at, 'four': None, 'outside': None,
                         'later': '2026-10-09T14:01:00Z', 'backward': None, 'short': None})
        self.assertEqual(align([dict(id='x', at=at, text='VOICE OF INTERPRETOR ' + text)],
                               [dict(begin=at, text='[speaking in French] ' + text.upper())]), {'x': at})
        self.assertEqual(align([dict(id='x', at=at, text=text)],
                               [dict(begin=at, text=text), dict(begin='2026-10-09T14:00:01Z', text=text)]), {'x': at})

    def test_12_performance(self):
        from watch.align import align
        _, rows = parse_transcript(fixture('HAN149-E.XML.gz'), fixture('HAN149-F.XML.gz'), source='hansard', number=149)
        lines = json.loads(fixture('captions-45735-en.json.gz'))
        started = time.monotonic()
        matches = align(interventions(rows), lines)
        self.assertLess(time.monotonic() - started, 10)
        self.assertGreaterEqual(sum(v is not None for v in matches.values()), 100)
