from contextlib import ExitStack
from datetime import datetime, timedelta, timezone
import gzip
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest

from watch.ingest import parse_members, parse_ministries
from watch.store import SCHEMA, alert_dict, connect
from watch.tests.test_records import fixture


FIXTURES = Path(__file__).parent / 'fixtures' / 'alerts'
API_KEYS = {'id', 'at', 'kind', 'follow', 'title', 'body', 'video', 'division'}


def load(name):
    return json.loads(gzip.decompress((FIXTURES / f'{name}.json.gz').read_bytes()))


def at(text):
    return datetime.fromisoformat(text)


def bill_follow(number, follow_id=None):
    return {'kind': 'bill', 'id': follow_id or 'f_' + number.lower().replace('-', ''), 'label': number,
            'bill': {'id': '45-1/' + number, 'number': number, 'title': 'T'}}


def mp_follow(person_id, name):
    return {'kind': 'mp', 'id': 'f_mp' + person_id, 'mp': {'person_id': person_id, 'name': name}}


def seed(db, data, source='archive'):
    event = dict(data['event'], captions=source)
    db.execute(f"INSERT INTO events VALUES ({','.join('?' * len(event))})", tuple(event.values()))
    db.executemany('INSERT INTO captions VALUES (?,?,?,?,?,?,?)',
                   [(c['event'], c['lang'], source, c['seq'], c['begin'], c['end'], c['text']) for c in data['captions']])
    db.executemany('INSERT INTO divisions VALUES (?,?,?,?,?,?,?,?,?,?)', [tuple(d.values()) for d in data.get('divisions', [])])


def index_for(db):
    from watch.speaker import CallIndex
    return CallIndex(db.execute('SELECT * FROM members'), db.execute('SELECT * FROM ministries'))


def line(db, seq, begin, text, event='45734', source='live'):
    db.execute('INSERT INTO captions VALUES (?,?,?,?,?,?,?)', (event, 'en', source, seq, begin, begin, text))


class AlertTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        stack = ExitStack()
        self.addCleanup(stack.close)
        self.db = stack.enter_context(connect(self.temp.name))

    def alerts(self):
        return [alert_dict(row) for row in self.db.execute('SELECT * FROM alerts ORDER BY at, id')]

    def test_01_bill_numbers(self):
        from watch.alerts import bill_numbers
        self.assertEqual(bill_numbers('We rise on Bill C-39, then projet de loi s-209, and C-3PO too'), ['C-39', 'S-209'])
        self.assertEqual(bill_numbers('bill c-39 and C-5.'), ['C-39', 'C-5'])
        self.assertEqual(bill_numbers('C-39x ABC-5 nothing'), [])

    def replay(self, data, follows, event=None):
        from watch.alerts import replay
        seed(self.db, data)
        return replay(self.db, data['event']['id'], follows, index_for(self.db))

    def test_02_vote_called(self):
        data = load('vote-45734')
        found = self.replay(data, [bill_follow('C-39')])
        self.assertEqual(len(found), 1)
        alert = found[0]
        self.assertEqual((alert['kind'], alert['title'], alert['follow'], alert['division']),
                         ('bill_vote', 'Vote called on Bill C-39', 'f_c39', None))
        self.assertEqual(alert['body'], 'Members are being called in for the vote.')
        call = next(c for c in data['captions'] if c['text'] == 'Call in the members.')
        event = data['event']
        base = at(event['recording_start']) - timedelta(seconds=event['preroll_s'])
        self.assertEqual(alert['at'], call['begin'])
        self.assertEqual(alert['video'], {'event': '45734', 'live': False,
                                          'offset_s': round((at(call['begin']) - base).total_seconds(), 3)})
        self.assertGreater(alert['video']['offset_s'], 3000)

    def test_03_other_bill_followed(self):
        self.assertEqual(self.replay(load('vote-45734'), [bill_follow('C-218')]), [])
        self.assertEqual(self.db.execute('SELECT count(*) FROM alerts').fetchone()[0], 0)

    def live(self, texts, source='live'):
        base = datetime(2026, 10, 8, 19, 0, tzinfo=timezone.utc)
        self.db.execute("INSERT INTO events VALUES ('45734','e','house',NULL,148,'d','x',NULL,NULL,0,0,"
                        "'2026-10-08T18:59:30Z',30.0,NULL,?, 'now')", (source,))
        for i, text in enumerate(texts):
            line(self.db, i, (base + timedelta(seconds=10 * i)).strftime('%Y-%m-%dT%H:%M:%S.123Z'), text, source=source)
        return base

    def test_04_dedupe(self):
        from watch.alerts import detect_votes
        base = self.live(['The question is on the motion that Bill C-39 be now read a second time.', 'Call in the members.'])
        now = base + timedelta(minutes=2)
        follows = [bill_follow('C-39')]
        self.assertEqual(len(detect_votes(self.db, now, follows)), 1)
        self.assertEqual(detect_votes(self.db, now, follows), [])
        self.assertEqual(len(self.alerts()), 1)
        self.assertEqual(len(detect_votes(self.db, now, follows + [bill_follow('C-39', 'f_second')])), 1)

    def test_05_stale_call(self):
        from watch.alerts import detect_votes
        base = self.live(['The question is on the motion that Bill C-39 be now read a second time.', 'Call in the members.'])
        follows = [bill_follow('C-39')]
        self.assertEqual(detect_votes(self.db, base + timedelta(minutes=11), follows), [])
        self.assertEqual(detect_votes(self.db, base + timedelta(seconds=5), follows), [])
        self.assertEqual(len(detect_votes(self.db, base + timedelta(minutes=9), follows)), 1)

    def test_06_split_phrase(self):
        from watch.alerts import detect_votes
        base = self.live(['Third reading of Bill C-39.', 'Now, call in the', 'members.', 'The bells are ringing.'])
        ids = detect_votes(self.db, base + timedelta(minutes=1), [bill_follow('C-39')])
        self.assertEqual(len(ids), 1)
        alert = self.alerts()[0]
        self.assertEqual(alert['at'], '2026-10-08T19:00:20.123Z')
        self.assertTrue(alert['video']['live'])
        self.assertEqual(self.db.execute('SELECT dedupe FROM alerts').fetchone()[0], 'bill_vote:f_c39:45734:2')

    def test_07_deferred_is_silent(self):
        data = load('deferred-44911')
        found = self.replay(data, [bill_follow('C-11')])
        self.assertEqual(found, [])
        # Anti-vacuity: the same window with a call line appended does alert.
        with connect(self.temp.name + '/other') as other:
            last = data['captions'][-1]
            extra = dict(last, seq=last['seq'] + 1, begin='2026-05-08T17:16:40.000Z', end='2026-05-08T17:16:41.000Z',
                         text='The question is on the motion that Bill C-11 be referred back to committee. Call in the members.')
            data['captions'].append(extra)
            seed(other, data)
            from watch.alerts import replay
            again = replay(other, data['event']['id'], [bill_follow('C-11')], index_for(other))
            self.assertEqual([a['title'] for a in again], ['Vote called on Bill C-11'])

    def test_08_bill_not_in_sentence(self):
        # The current questions name Part 1 / Part 2, not a bill. Do not borrow C-5
        # from the earlier third-reading question, or from the deferral announcement.
        self.assertEqual(len(self.replay(load('vote-45734'), [bill_follow('C-39')])), 1)
        self.assertEqual(self.replay(load('vote-43209'), [bill_follow('C-5')]), [])

    def test_15_electronic_vote_without_members_call(self):
        self.assertIn('call in the members',
                      ' '.join(c['text'] for c in load('vote-45734')['captions']).lower())
        data = load('electronic-45549')
        text = ' '.join(c['text'] for c in data['captions'])
        self.assertNotIn('call in the members', text.lower())
        found = self.replay(data, [bill_follow('C-232')])
        self.assertEqual([a['title'] for a in found], ['Vote called on Bill C-232'])
        # This is the start announcement, before the repeated recorded-vote markers.
        self.assertEqual(found[0]['at'], '2026-06-10T19:57:50.645Z')

    def test_16_adjournment_does_not_borrow_debated_bill(self):
        self.assertEqual(len(self.replay(load('vote-45734'), [bill_follow('C-39')])), 1)
        data = load('adjournment-45553')
        text = ' '.join(c['text'] for c in data['captions']).lower()
        self.assertIn('c-9', text)
        self.assertIn('house now adjourn', text)
        self.assertIn('call in the members', text)
        self.assertEqual(self.replay(data, [bill_follow('C-9')]), [])

    def test_17_multiple_triggers_are_one_vote_across_polls(self):
        from watch.alerts import detect_votes
        data = load('vote-45734')
        text = ' '.join(c['text'] for c in data['captions']).lower()
        self.assertIn('call in the members', text)
        self.assertIn('has started', text)
        self.assertGreater(text.count('calling of recorded vote'), 3)
        found = self.replay(data, [bill_follow('C-39')])
        self.assertEqual(len(found), 1)
        self.assertEqual(found[0]['at'], '2026-10-08T19:15:25.371Z')
        self.assertEqual(detect_votes(self.db, at(data['captions'][-1]['begin']),
                                      [bill_follow('C-39')], source='archive'), [])

    def test_18_stacked_deferred_votes_name_each_bill_once(self):
        found = self.replay(load('stacked-45549'), [bill_follow('C-20'), bill_follow('C-232')])
        self.assertEqual([a['title'] for a in found],
                         ['Vote called on Bill C-20', 'Vote called on Bill C-232'])
        self.assertEqual(len({a['follow'] for a in found}), 2)

    def test_19_split_electronic_caption(self):
        found = self.replay(load('electronic-45733'), [bill_follow('C-218')])
        self.assertEqual([a['title'] for a in found], ['Vote called on Bill C-218'])
        self.assertEqual(found[0]['at'], '2026-10-07T19:49:06.916Z')

    def test_20_measure_matches_early_stacked_timestamps(self):
        from watch.alerts import measure
        seed(self.db, load('stacked-45549'))
        self.db.commit()
        result = measure(Path(self.temp.name) / 'watch.db')
        self.assertEqual((result['events'], result['called'], result['matched'],
                          result['divisions_in_window'], result['recall'], result['precision']),
                         (1, 2, 2, 2, 1.0, 1.0))
        self.assertEqual(result['misses'], [])
        self.assertEqual(result['false_alerts'], [])

    def test_21_one_call_matches_multiple_same_bill_divisions(self):
        from watch.alerts import measure
        seed(self.db, load('same-bill-45554'))
        self.db.commit()
        result = measure(Path(self.temp.name) / 'watch.db')
        self.assertEqual((result['called'], result['matched'], result['divisions_in_window'],
                          result['recall'], result['precision']), (1, 1, 2, 1.0, 1.0))
        self.assertEqual(result['misses'], [])
        self.assertEqual(result['false_alerts'], [])

    def test_22_closure_does_not_borrow_debated_bill(self):
        self.assertEqual(len(self.replay(load('vote-45734'), [bill_follow('C-39')])), 1)
        data = load('closure-45552')
        text = ' '.join(c['text'] for c in data['captions']).lower()
        self.assertIn('c-30', text)
        self.assertIn('debate not be further adjourned', text)
        self.assertIn('call in the members', text)
        self.assertEqual(self.replay(data, [bill_follow('C-30')]), [])

    def test_23_procedural_motion_names_bill_but_is_not_bill_vote(self):
        self.assertEqual(len(self.replay(load('vote-45734'), [bill_follow('C-39')])), 1)
        data = load('procedural-45552')
        text = ' '.join(c['text'] for c in data['captions']).lower()
        self.assertIn('bill c-30', text)
        self.assertIn('be disposed off as follows', text)
        self.assertIn('call in the members', text)
        self.assertEqual(self.replay(data, [bill_follow('C-30')]), [])

    def test_24_question_names_number_without_word_bill(self):
        found = self.replay(load('numbered-question-43209'), [bill_follow('C-5')])
        self.assertEqual([a['title'] for a in found], ['Vote called on Bill C-5'])
        self.assertEqual(found[0]['at'], '2025-06-20T17:51:32.880Z')

    def division(self, when, bill='45-1/C-39', ident='45-1/178'):
        self.db.execute('INSERT INTO divisions VALUES (?,178,?,?,?,?,172,143,5,0)',
                        (ident, when.strftime('%Y-%m-%dT%H:%M:%SZ'), bill, '2nd reading of Bill C-39', 'agreed'))

    def test_09_divisions(self):
        from watch.alerts import detect_divisions
        now = datetime(2026, 10, 9, 12, 0, tzinfo=timezone.utc)
        follows = [bill_follow('C-39')]
        self.division(now - timedelta(hours=1))
        self.division(now - timedelta(hours=25), ident='45-1/177')
        self.division(now - timedelta(hours=1), bill='45-1/C-12', ident='45-1/179')
        self.division(now - timedelta(hours=1), bill=None, ident='45-1/180')
        self.assertEqual(len(detect_divisions(self.db, now, follows)), 1)
        self.assertEqual(detect_divisions(self.db, now, follows), [])
        alert = self.alerts()[0]
        self.assertEqual(alert, dict(
            id=alert['id'], at='2026-10-09T11:00:00Z', kind='bill_vote', follow='f_c39',
            title='Vote on Bill C-39: agreed', body='Yeas 172, nays 143.', video=None,
            division=dict(id='45-1/178', number=178, bill='45-1/C-39', description='2nd reading of Bill C-39',
                          result='agreed', yeas=172, nays=143, paired=5)))

    def speaker(self):
        data = load('speaker-45552')
        seed(self.db, data, source='live')
        self.db.executemany('INSERT INTO members VALUES (?,?,?,?,?,?,?)', data['members'])
        self.db.executemany('INSERT INTO ministries VALUES (?,?,?)', data['ministries'])
        person = next(m for m in data['members'] if 'Fanshawe' in m[3])
        return data, person, index_for(self.db)

    def test_10_speaking(self):
        from watch.alerts import detect_speaking
        data, person, index = self.speaker()
        now = at('2026-06-15T20:54:00Z')
        other = next(m for m in data['members'] if m[0] != person[0])
        self.assertEqual(detect_speaking(self.db, now, [mp_follow(other[0], other[1])], index), [])
        ids = detect_speaking(self.db, now, [mp_follow(person[0], person[1])], index)
        self.assertEqual(len(ids), 1)
        alert = self.alerts()[0]
        self.assertEqual((alert['kind'], alert['title'], alert['at']),
                         ('mp_speaking', f'{person[1]} is speaking', '2026-06-15T20:53:24.698Z'))
        self.assertEqual(alert['body'], f"House of Commons, sitting {data['event']['number']} - named by the Speaker (riding)")
        base = at(data['event']['recording_start']) - timedelta(seconds=data['event']['preroll_s'])
        self.assertEqual(alert['video'], {'event': '45552', 'live': True,
                                          'offset_s': round((at('2026-06-15T20:53:24.698Z') - base).total_seconds(), 3)})
        self.assertEqual(detect_speaking(self.db, now, [mp_follow(person[0], person[1])], index), [])

    def test_11_member_has_not_started(self):
        from watch.alerts import detect_speaking
        data, person, index = self.speaker()
        # Drop everything after the call: no later ">>" exists yet.
        self.db.execute("UPDATE captions SET text='>> The Speaker: The honourable member for London--Fanshawe.' WHERE seq=2927")
        self.db.execute('DELETE FROM captions WHERE seq>2927')
        now = at('2026-06-15T20:54:00Z')
        self.assertEqual(detect_speaking(self.db, now, [mp_follow(person[0], person[1])], index), [])
        # Anti-vacuity: the next speech beginning makes the same call alert.
        line(self.db, 2928, '2026-06-15T20:53:28.000Z', '>> Thank you, Mr. Speaker.', event='45552')
        self.assertEqual(len(detect_speaking(self.db, now, [mp_follow(person[0], person[1])], index)), 1)

    def test_12_run(self):
        from watch.alerts import run
        base = self.live(['The question is on the motion that Bill C-39 be now read a second time.', 'Call in the members.'])
        self.db.execute('INSERT INTO follows(id,created_at,body) VALUES (?,?,?)',
                        ('f_c39', 'now', json.dumps(bill_follow('C-39'))))
        self.division(base, ident='45-1/178')
        self.db.commit()
        now = base + timedelta(minutes=2)
        ids = run(self.temp.name, now)
        self.assertEqual(len(ids), 2)
        rows = self.db.execute('SELECT * FROM alerts ORDER BY id').fetchall()
        self.assertEqual({r['id'] for r in rows}, set(ids))
        for row in rows:
            self.assertEqual(set(alert_dict(row)), API_KEYS)
        self.assertEqual(sorted(r['dedupe'] for r in rows), ['bill_vote:f_c39:45734:1', 'division:f_c39:45-1/178'])
        meta = json.loads(self.db.execute("SELECT value FROM meta WHERE key='source:alerts'").fetchone()[0])
        self.assertEqual(meta, {'at': '2026-10-08T19:02:00Z', 'ok': True, 'error': None})
        self.assertEqual(run(self.temp.name, now), [])

    def test_13_run_isolates_failures(self):
        from unittest import mock
        from watch import alerts
        base = self.live(['The question is on the motion that Bill C-39 be now read a second time.', 'Call in the members.'])
        self.db.execute('INSERT INTO follows(id,created_at,body) VALUES (?,?,?)',
                        ('f_c39', 'now', json.dumps(bill_follow('C-39'))))
        self.db.commit()
        with mock.patch.object(alerts, 'detect_divisions', side_effect=RuntimeError('boom')):
            ids = alerts.run(self.temp.name, base + timedelta(minutes=2))
        self.assertEqual(len(ids), 1)
        meta = json.loads(self.db.execute("SELECT value FROM meta WHERE key='source:alerts'").fetchone()[0])
        self.assertEqual((meta['ok'], meta['error']), (False, 'boom'))

    def test_14_surname_call_is_too_weak(self):
        from watch.alerts import detect_speaking
        members = parse_members(fixture('members.xml.gz'))
        self.db.executemany('INSERT INTO members VALUES (?,?,?,?,?,?,?)', members)
        index = index_for(self.db)
        person = next(m for m in members if len(index.lasts[m[6].lower()]) == 1 and index.call(f'Mr. {m[6]}.', committee=True))
        self.assertEqual(index.call(f'Mr. {person[6]}.', committee=True)[1:], (0.6, 'surname'))
        self.db.execute("INSERT INTO events VALUES ('45822','e','committee','INDU',50,'d','x',NULL,NULL,0,0,"
                        "'2026-10-06T15:04:02Z',30.0,NULL,'live','now')")
        for i, text in enumerate([f'>> The Chair: Mr. {person[6]}.', '>> Thank you, Chair.']):
            line(self.db, i, f'2026-10-06T15:10:0{i}.000Z', text, event='45822')
        now = at('2026-10-06T15:11:00Z')
        self.assertEqual(detect_speaking(self.db, now, [mp_follow(person[0], person[1])], index), [])
        # Anti-vacuity: a riding call in the same committee setting alerts.
        riding = next(m for m in members if index.call(f'The member for {m[3]}.') == (m[0], 0.9, 'riding'))
        self.db.execute('UPDATE captions SET text=? WHERE seq=0', (f'>> The Chair: The member for {riding[3]}.',))
        self.assertEqual(len(detect_speaking(self.db, now, [mp_follow(riding[0], riding[1])], index)), 1)
        self.assertIn('INDU, meeting 50 - named by the Speaker (riding)', self.alerts()[0]['body'])


if __name__ == '__main__':
    unittest.main()
