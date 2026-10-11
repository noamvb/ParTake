from contextlib import redirect_stdout
from datetime import datetime, timezone
import io
import json
import tempfile
import unittest

from watch.poll import _save_transcript
from watch.store import connect
from watch.tests.test_records import fixture
from watch.tests.test_segment import seed, insert_lines


class AccuracyTests(unittest.TestCase):
    def test_11_measure(self):
        from watch.accuracy import measure, main
        from watch.segment import segment_event
        with tempfile.TemporaryDirectory() as data:
            results = []
            for event, stem, source, number, committee in [('45735', 'HAN149', 'hansard', 149, None),
                                                         ('45822', 'INDUEV50', 'evidence', 50, 'INDU')]:
                with connect(data) as db, db:
                    index = seed(db, event)
                    insert_lines(db, json.loads(fixture(f'captions-{event}-en.json.gz')))
                    segment_event(db, event, index)
                _save_transcript(data, fixture(stem + '-E.XML.gz'), fixture(stem + '-F.XML.gz'),
                                 source, number, committee, datetime.now(timezone.utc))
                with connect(data) as db:
                    result = measure(db, event)
                results.append(result)
                self.assertEqual(set(result), {'event', 'document', 'interventions', 'aligned', 'evaluable', 'guessed',
                                 'correct', 'precision', 'recall', 'by_how', 'errors'})
                self.assertEqual(set(result['by_how']), {'riding', 'portfolio', 'surname'})
                self.assertLessEqual(len(result['errors']), 20)
                self.assertTrue(all(set(e) == {'intervention', 'expected', 'guessed', 'how', 'text'} for e in result['errors']))
                self.assertEqual(result['precision'], result['correct'] / result['guessed'] if result['guessed'] else None)
                self.assertEqual(result['recall'], result['correct'] / result['evaluable'] if result['evaluable'] else None)
                if event == '45735':
                    self.assertGreaterEqual(result['aligned'], 100)
                    self.assertEqual((result['guessed'], result['correct']), (33, 29))
                else:
                    self.assertEqual((result['guessed'], result['correct']), (1, 1))
            output = io.StringIO()
            with redirect_stdout(output):
                self.assertEqual(main(['--data', data, '--event', '45735', '--event', '45822']), 0)
            self.assertEqual([json.loads(line) for line in output.getvalue().splitlines()], results)
