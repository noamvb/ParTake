import unittest

from watch.ingest import parse_members, parse_ministries
from watch.tests.test_records import fixture


class SpeakerTests(unittest.TestCase):
    def setUp(self):
        from watch.speaker import CallIndex
        self.members = parse_members(fixture('members.xml.gz'))
        self.ministries = parse_ministries(fixture('ministries.xml.gz'))
        self.index = CallIndex(self.members, self.ministries)

    def test_01_label(self):
        from watch.speaker import PRESIDING, label
        self.assertEqual(label('>> The Speaker: Orders of the day.'), 'The Speaker')
        self.assertEqual(label('>> Voice of Interpreter: ...'), 'Voice of Interpreter')
        self.assertIsNone(label('>> Thank you, Mr. Speaker.'))
        for name in PRESIDING:
            self.assertEqual(label('>> ' + name.upper() + ': text'), name)
        self.assertEqual(label('>> (Voice of Interpreter): text'), 'Voice of Interpreter')

    def test_02_riding_exact(self):
        person = next(r[0] for r in self.members if r[3] == 'Edmonton Northwest')
        self.assertEqual(person, '123447')
        self.assertEqual(self.index.call('The honourable member for Edmonton Northwest.'),
                         ('123447', 0.9, 'riding'))
        self.assertEqual(self.index.call('The member for Oakville West. The member for Edmonton Northwest.'),
                         ('123447', 0.9, 'riding'))

    def test_03_riding_fuzzy(self):
        from watch.speaker import CallIndex
        self.assertEqual(self.index.call('The member for Edmonton Northwesx.'), ('123447', 0.75, 'riding'))
        self.assertEqual(self.index.call('The member for Saint Catharines.'), ('88934', 0.9, 'riding'))
        rows = [('a', 'A', '', 'North Ab', '', 'A', 'A'), ('b', 'B', '', 'North Ac', '', 'B', 'B')]
        self.assertIsNone(CallIndex(rows, []).call('The member for North Ad.'))
        self.assertIsNone(CallIndex(rows + [('c', 'C', '', 'North Ab', '', 'C', 'C')], []).call('member for North Ab.'))

    def test_04_portfolio_and_surname(self):
        person = next(r[0] for r in self.ministries if r[1] == 'Minister of Indigenous Services')
        self.assertEqual(person, '122492')
        self.assertEqual(self.index.call('The Honourable Minister of Indigenous Services.'), ('122492', 0.85, 'portfolio'))
        self.assertEqual(self.index.call('Minister for Indigenous Services.'), ('122492', 0.85, 'portfolio'))
        self.assertEqual(self.index.call('The Prime Minister.'), ('28286', 0.85, 'portfolio'))
        self.assertEqual(self.index.call('Madame Rempel Garner, go ahead.', committee=True), ('71902', 0.6, 'surname'))
        self.assertIsNone(self.index.call('Mr. Davies, go ahead.', committee=True))
        self.assertIsNone(self.index.call('Mr. Masse, go ahead.', committee=True))
        self.assertIsNone(self.index.call('Madame Rempel Garner, go ahead.'))
        self.assertEqual(self.index.call('Mr. Davies, then Monsieur Bittle, go ahead.', committee=True), ('88934', 0.6, 'surname'))

    def test_13_riding_call_noise(self):
        self.assertEqual(self.index.call('The member for Edmonton Northwesx, go ahead. [ Applause ]'),
                         ('123447', 0.75, 'riding'))
        self.assertEqual(self.index.call('The member for Edmonton Northwesx [ Speaking French ].'),
                         ('123447', 0.75, 'riding'))
        self.assertEqual(self.index.call('The member for Edmonton Northwesx with three minutes for his speech.'),
                         ('123447', 0.75, 'riding'))

    def test_14_bracketed_interpreter(self):
        from watch.speaker import label
        self.assertEqual(label('>> [Voice of Interpreter]: Thank you.'), 'Voice of Interpreter')
        self.assertEqual(label('>> [Interpreter]: Thank you.'), 'Interpreter')
