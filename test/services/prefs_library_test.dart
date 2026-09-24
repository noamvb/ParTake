import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:parlvu/parlvu.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:partake/core/library.dart';
import 'package:partake/services/prefs_library.dart';

WatchRecord rec(
  int id,
  DateTime updated, {
  int position = 1000,
  int? duration = 6000000,
}) => WatchRecord(
  eventId: id,
  title: 'Event $id',
  eventDate: DateTime.utc(2026, 9, 23),
  position: Duration(milliseconds: position),
  duration: duration == null ? null : Duration(milliseconds: duration),
  updatedAt: updated,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('fresh preferences have defaults', () async {
    SharedPreferences.setMockInitialValues({});
    final lib = PrefsLibrary(await SharedPreferences.getInstance());
    expect(lib.follows, isEmpty);
    expect(lib.continueWatching, isEmpty);
    expect(lib.settings.language, AudioLanguage.floor);
    expect(lib.settings.captions, isTrue);
  });

  test('follows persist and notify once per update', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final lib = PrefsLibrary(prefs);
    var count = 0;
    lib.addListener(() => count++);
    await lib.setFollowed('HOC', true);
    await lib.setFollowed('FEWO', true);
    await lib.setFollowed('HOC', false);
    expect(lib.follows, {'FEWO'});
    expect(PrefsLibrary(prefs).follows, {'FEWO'});
    expect(count, 3);
  });

  test('progress replaces by id and persists complete record', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final lib = PrefsLibrary(prefs);
    final t = DateTime.utc(2026);
    await lib.saveProgress(rec(1, t, position: 10000));
    await lib.saveProgress(
      rec(1, t.add(const Duration(seconds: 1)), position: 20000),
    );
    await lib.saveProgress(rec(2, t));
    final fresh = PrefsLibrary(prefs);
    expect(fresh.record(1)!.position, const Duration(seconds: 20));
    final a = lib.record(1)!;
    final b = fresh.record(1)!;
    expect(
      [b.eventId, b.eventDate, b.position, b.duration, b.updatedAt],
      [a.eventId, a.eventDate, a.position, a.duration, a.updatedAt],
    );
  });

  test('continue watching filters finished and sorts newest first', () async {
    SharedPreferences.setMockInitialValues({});
    final lib = PrefsLibrary(await SharedPreferences.getInstance());
    final t = DateTime.utc(2026);
    await lib.saveProgress(rec(1, t));
    await lib.saveProgress(rec(2, t.add(const Duration(minutes: 1))));
    await lib.saveProgress(
      rec(3, t.add(const Duration(minutes: 2)), position: 99, duration: 100),
    );
    expect(lib.continueWatching.map((r) => r.eventId), [2, 1]);
  });

  test('history is capped at 200 newest records', () async {
    SharedPreferences.setMockInitialValues({});
    final lib = PrefsLibrary(await SharedPreferences.getInstance());
    final t = DateTime.utc(2026);
    for (var i = 0; i < 205; i++) {
      await lib.saveProgress(rec(i, t.add(Duration(seconds: i))));
    }
    expect(
      jsonDecode((await SharedPreferences.getInstance()).getString('history')!)
          as List,
      hasLength(200),
    );
    expect(lib.record(0), isNull);
    expect(lib.record(4), isNull);
    expect(lib.record(5), isNotNull);
  });

  test(
    'corrupt history entries are skipped and malformed JSON is tolerated',
    () async {
      SharedPreferences.setMockInitialValues({
        'history': '[{"eventId":1,"title":"ok","eventDate":"2026-09-23","positionMs":1000,"durationMs":null,"updatedAt":"2026-09-23T18:00:00.000Z"},{"eventId":"bad"}]',
      });
      final lib = PrefsLibrary(await SharedPreferences.getInstance());
      expect(lib.record(1), isNotNull);
      expect(lib.record(0), isNull);
      SharedPreferences.setMockInitialValues({'history': 'not json'});
      expect(
        PrefsLibrary(await SharedPreferences.getInstance()).continueWatching,
        isEmpty,
      );
    },
  );

  test('settings persist', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final lib = PrefsLibrary(prefs);
    await lib.updateSettings(
      const AppSettings(language: AudioLanguage.english, captions: false),
    );
    expect(prefs.getString('settings.language'), 'en');
    expect(prefs.getBool('settings.captions'), false);
    expect(PrefsLibrary(prefs).settings.language, AudioLanguage.english);
    expect(PrefsLibrary(prefs).settings.captions, false);
  });
}
