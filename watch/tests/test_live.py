import configparser
from datetime import timedelta
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import call, patch

from watch.store import connect, iso
from watch.tests.test_parlvu import NOW, PAGE, UPCOMING, SD_URL, fixture


class Units:
    def __init__(self, active=()):
        self.running = set(active)
        self.started = []

    def active(self):
        return self.running.copy()

    def start(self, event_id):
        self.started.append(event_id)
        self.running.add(event_id)


class LiveTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.data = Path(self.temp.name)
        upcoming = json.loads(fixture('parlvu-upcoming.json'))
        self.rows = [row for group in upcoming['ContentEntityDatas'] for row in group]
        for row in self.rows:
            if str(row['Id']) == '45873':
                row['EntityStatus'] = 1
        self.house = next(row for row in self.rows if str(row['Id']) == '45873')
        self.units = Units()
        self.failures = {}
        self.calls = []

    def fetch(self, url):
        self.calls.append(url)
        if url in self.failures:
            raise self.failures[url]
        if url == UPCOMING:
            return json.dumps({'ContentEntityDatas': [self.rows]}).encode()
        if url.startswith(PAGE):
            return fixture('parlvu-event-45735.html.gz')
        self.fail('unexpected URL: ' + url)

    def tick(self, **kwargs):
        from watch.live import tick
        return tick(self.data, self.fetch, NOW, self.units, **kwargs)

    def follow(self, code, removed=False):
        with connect(self.data) as db, db:
            db.execute('INSERT INTO follows(id,created_at,body,removed_at) VALUES (?,?,?,?)',
                       (code, iso(NOW), json.dumps({'kind': 'committee', 'committee': {'code': code}}),
                        iso(NOW) if removed else None))

    def committee(self, event_id, code, hour):
        return dict(self.house, Id=int(event_id), Title=code + ' Meeting No. 1',
                    ScheduledStart=f'2026-10-19T{hour:02}:00:00')

    def test_01_live_house_page_and_start(self):
        result = self.tick()
        self.assertEqual(result, {'wanted': ['45873'], 'started': ['45873'], 'active': ['45873']})
        self.assertEqual(self.units.started, ['45873'])
        with connect(self.data) as db:
            row = db.execute("SELECT * FROM events WHERE id='45873'").fetchone()
            self.assertEqual((row['stream_url'], row['recording_start'], row['preroll_s']),
                             (SD_URL, '2026-10-09T14:01:04Z', 30.0))
            for key in ('raw:parlvu/upcoming', 'raw:parlvu/event/45873'):
                self.assertIsNotNone(db.execute('SELECT value FROM meta WHERE key=?', (key,)).fetchone())
        self.assertTrue(list((self.data / 'raw' / 'parlvu_pages').glob('*.jsonl.gz')))
        self.calls.clear()
        self.tick()
        self.assertEqual(self.calls, [UPCOMING])

    def test_02_already_active(self):
        self.units = Units(['45873'])
        self.assertEqual(self.tick()['started'], [])
        self.assertEqual(self.units.started, [])

    def test_03_committee_filter(self):
        self.rows = [self.committee('1', 'INDU', 9), self.committee('2', 'TRAN', 10)]
        self.assertEqual(self.tick()['started'], [])
        self.follow('INDU')
        self.follow('TRAN', removed=True)
        self.assertEqual(self.tick()['started'], ['1'])
        self.assertEqual(self.units.started, ['1'])

    def test_04_cap_house_and_earliest_committees(self):
        self.rows = [self.committee('3', 'INDU', 11), self.committee('2', 'INDU', 10),
                     self.house, self.committee('1', 'INDU', 9)]
        self.follow('INDU')
        self.assertEqual(self.tick(max_recorders=3)['wanted'], ['45873', '1', '2'])
        self.assertEqual(self.units.started, ['45873', '1', '2'])
        self.units = Units(['old1', 'old2', 'old3'])
        self.assertEqual(self.tick(max_recorders=3)['started'], [])

    def test_05_page_failure_continues_and_retries(self):
        self.rows = [self.house, self.committee('1', 'INDU', 9)]
        self.follow('INDU')
        self.failures[PAGE + '45873'] = RuntimeError('broken event page')
        self.assertEqual(self.tick()['started'], ['1'])
        with connect(self.data) as db:
            health = json.loads(db.execute("SELECT value FROM meta WHERE key='source:live'").fetchone()[0])
        self.assertEqual(health['at'], iso(NOW))
        self.assertFalse(health['ok'])
        self.assertIn('broken event page', health['error'])
        self.failures.clear()
        self.assertEqual(self.tick()['started'], ['45873'])
        with connect(self.data) as db:
            self.assertTrue(json.loads(db.execute("SELECT value FROM meta WHERE key='source:live'").fetchone()[0])['ok'])
        self.failures[UPCOMING] = RuntimeError('upcoming offline')
        self.assertEqual(self.tick()['active'], ['1', '45873'])

    def test_06_unit_literals(self):
        root = Path(__file__).parents[1] / 'systemd'
        services = {
            'live': ('watch.live --data %h/.local/share/partake-watch --ollama http://127.0.0.1:11436', '150M'),
            'recorder@': ('watch.recorder --data %h/.local/share/partake-watch --event %i', '80M'),
            'digest-evening': ('watch.digest --data %h/.local/share/partake-watch --kind evening', '150M'),
            'digest-morning': ('watch.digest --data %h/.local/share/partake-watch --kind morning', '150M')}
        for name, (command, memory) in services.items():
            unit = configparser.ConfigParser(strict=False, interpolation=None)
            self.assertTrue(unit.read(root / ('partake-watch-' + name + '.service')))
            self.assertEqual(unit['Service']['ExecStart'], '/usr/bin/python3 -m ' + command)
            self.assertEqual(unit['Service']['MemoryMax'], memory)
            self.assertEqual(unit['Service']['WorkingDirectory'], '%h/partake')
            if name == 'recorder@':
                self.assertEqual(unit['Unit']['StartLimitIntervalSec'], '900')
                self.assertEqual(unit['Unit']['StartLimitBurst'], '6')
                self.assertEqual(unit['Service']['RestartSec'], '15')
                self.assertEqual(unit['Service']['CPUQuota'], '25%')
            if name in ('live', 'recorder@'):
                self.assertEqual(unit['Service']['Restart'], 'on-failure')
            else:
                self.assertEqual(unit['Service']['Type'], 'oneshot')
            if name == 'live':
                for key in ('After', 'Wants'):
                    self.assertIn('partake-watch-embed.service', unit['Unit'][key])
        for kind, calendar in [('evening', '*-*-* 19:30:00 America/Toronto'),
                               ('morning', '*-*-* 11:00:00 America/Toronto')]:
            unit = configparser.ConfigParser(strict=False, interpolation=None)
            self.assertTrue(unit.read(root / ('partake-watch-digest-' + kind + '.timer')))
            self.assertEqual(unit['Timer']['OnCalendar'], calendar)
            self.assertEqual(unit['Timer']['Persistent'], 'true')
            if kind == 'morning':
                self.assertIn('OnCalendar=*-*-* 06..10:00,30:00 America/Toronto',
                              (root / 'partake-watch-digest-morning.timer').read_text())
        self.assertIn('--sources hansard,evidence,votes,bills,parlvu',
                      (root / 'partake-watch-poll.service').read_text())

    def test_07_main_worker_windows(self):
        from watch.live import main
        elapsed = [0]
        sleeps = []
        def sleep(seconds):
            sleeps.append(seconds)
            elapsed[0] += seconds
        with patch('watch.worker.main', return_value=0) as worker:
            self.assertEqual(main(['--data', str(self.data), '--ollama', 'http://test',
                                   '--interval', '60', '--work-every', '120'],
                                  fetch=self.fetch, now=lambda: NOW + timedelta(seconds=elapsed[0]),
                                  units=self.units, sleep=sleep, monotonic=lambda: elapsed[0], max_ticks=3), 0)
        self.assertEqual(worker.call_args_list, [call(['--data', str(self.data), '--ollama', 'http://test'])] * 2)
        self.assertEqual(sleeps, [60, 60])
        self.assertEqual(self.calls.count(UPCOMING), 3)
        self.rows = [dict(self.house, EntityStatus=-1)]
        self.units = Units()
        with patch('watch.worker.main') as worker:
            main(['--data', str(self.data)], fetch=self.fetch, units=self.units,
                 sleep=sleep, max_ticks=3)
        worker.assert_not_called()

    def test_08_systemctl_adapter(self):
        from watch.live import SystemdUnits
        from subprocess import CompletedProcess
        commands = []
        def run(argv, **kwargs):
            commands.append(argv)
            if 'list-units' in argv:
                return CompletedProcess(argv, 0, 'partake-watch-recorder@45873.service loaded active running\n')
            return CompletedProcess(argv, 0, 'active\n')
        with patch('watch.live.subprocess.run', side_effect=run):
            units = SystemdUnits()
            self.assertEqual(units.active(), {'45873'})
            units.start('45873')
        self.assertEqual(commands, [
            ['systemctl', '--user', 'list-units', 'partake-watch-recorder@*', '--state=active', '--plain', '--no-legend'],
            ['systemctl', '--user', 'is-active', 'partake-watch-recorder@45873.service'],
            ['systemctl', '--user', 'reset-failed', 'partake-watch-recorder@45873.service'],
            ['systemctl', '--user', 'start', 'partake-watch-recorder@45873.service']])


class AlertTickTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.data = Path(self.temp.name)

    def test_09_alerting_only_while_recording(self):
        from watch.live import main
        test = LiveTests('test_01_live_house_page_and_start')
        test.setUp()
        self.addCleanup(test.temp.cleanup)
        seen = []
        with patch('watch.worker.main', return_value=0):
            main(['--data', str(test.data)], fetch=test.fetch, now=lambda: NOW, units=test.units,
                 sleep=lambda s: None, monotonic=lambda: 0, max_ticks=2,
                 alerting=lambda data, now: seen.append((data, now)))
        self.assertEqual(seen, [(str(test.data), NOW)] * 2)
        test.rows = [dict(test.house, EntityStatus=-1)]
        test.units = Units()
        seen.clear()
        with patch('watch.worker.main', return_value=0):
            main(['--data', str(test.data)], fetch=test.fetch, now=lambda: NOW, units=test.units,
                 sleep=lambda s: None, max_ticks=2, alerting=lambda data, now: seen.append(now))
        self.assertEqual(seen, [])

    def test_10_alert_tick_pushes_and_survives_errors(self):
        from watch.live import alert_tick
        from watch.store import add_alert
        with connect(self.data) as db, db:
            db.execute("INSERT INTO push_devices VALUES ('fold','fcm','tok',?,NULL)",
                       (iso(NOW - timedelta(hours=1)),))
            add_alert(db, dict(at=iso(NOW - timedelta(minutes=1)), kind='mp_speaking', follow='f_x',
                               title='Bardish Chagger is speaking', body='House', video=None, division=None),
                      'test:1')
        sent = []

        class Sender:
            def send(self, token, data):
                sent.append((token, data))
                return True, None, False
        result = alert_tick(self.data, NOW, sender_from=lambda data: Sender())
        self.assertEqual(result['push']['sent'], 1)
        self.assertEqual([token for token, _ in sent], ['tok'])
        self.assertEqual(json.loads(sent[0][1]['alert'])['title'], 'Bardish Chagger is speaking')
        with patch('watch.alerts.run', side_effect=RuntimeError('boom')):
            self.assertIsNone(alert_tick(self.data, NOW, sender_from=lambda data: Sender()))
        self.assertEqual(len(sent), 1)
