import 'dart:convert';
import 'dart:io';

import 'package:parlvu/src/alignment.dart';
import 'package:parlvu/src/openparliament.dart';
import 'package:parlvu/src/models.dart';
import 'package:parlvu/src/time.dart';
import 'package:test/test.dart';

Speech speech(DateTime b, String words) => Speech(
  bucketTime: b,
  speaker: 'A',
  politicianUrl: null,
  textEn: words,
  procedural: false,
  url: '/x/',
);
Caption cap(DateTime t, String s) =>
    Caption(begin: t, end: t.add(const Duration(seconds: 1)), text: s);
DateTime local(String s) => parliamentTime('2026-07-07 $s');

void main() {
  test(
    'matches opening words across captions after removing interpreter cue',
    () {
      final t = local('11:00:00');
      final marks = alignSpeeches(
        [
          speech(
            t.subtract(const Duration(seconds: 60)),
            "Thank you very much, Madam Chair, for the invitation today.",
          ),
        ],
        [
          cap(t, '>> Voice of Interpreter: Thank you'),
          cap(
            t.add(const Duration(seconds: 2)),
            'very much Madam Chair for the',
          ),
          cap(t.add(const Duration(seconds: 4)), 'invitation today'),
        ],
      );
      expect(marks.single.source, MarkSource.captionMatch);
      expect(marks.single.wallClock, t);
      final lowerEdge = alignSpeeches(
        [
          speech(
            t.add(const Duration(seconds: 60)),
            'one two three four five six seven eight',
          ),
        ],
        [cap(t, 'one two three four five six seven eight')],
      );
      expect(lowerEdge.single.source, MarkSource.captionMatch);
      expect(lowerEdge.single.wallClock, t);
      final thresholdEdge = alignSpeeches(
        [speech(t, 'one two three four five six seven eight')],
        [cap(t, 'one two three four five unrelated unrelated unrelated')],
      );
      expect(thresholdEdge.single.source, MarkSource.captionMatch);
    },
  );

  test('interpolates within buckets and clamps monotonically and to a later anchor', () {
    final b = local('11:00:00');
    final a = alignSpeeches([
      speech(b, List.filled(10, 'a').join(' ')),
      speech(b, List.filled(30, 'b').join(' ')),
      speech(b, List.filled(60, 'c').join(' ')),
      speech(
        b.subtract(const Duration(minutes: 5)),
        List.filled(5, 'd').join(' '),
      ),
    ], []);
    expect(a.map((m) => m.wallClock), [
      b,
      b.add(const Duration(seconds: 30)),
      b.add(const Duration(seconds: 120)),
      b.add(const Duration(seconds: 120)),
    ]);
    final key = 'one two three four five six seven eight';
    final anchored = alignSpeeches(
      [
        speech(b, List.filled(50, 'w').join(' ')),
        speech(b, List.filled(50, 'x').join(' ')),
        speech(b, key),
      ],
      [cap(b.add(const Duration(seconds: 60)), key)],
    );
    expect(anchored[0].wallClock, b);
    expect(anchored[1].wallClock, b.add(const Duration(seconds: 60)));
    expect(anchored[2].source, MarkSource.captionMatch);
  });

  test('clamps to a later match in the next bucket without moving it', () {
    final b = local('11:00:00');
    String filler(String p, int n) => List.generate(n, (i) => '$p$i').join(' ');
    const key = 'alpha bravo charlie delta echo foxtrot golf hotel';
    final marks = alignSpeeches(
      [
        speech(b, filler('w', 90)),
        speech(b, filler('x', 10)),
        speech(b.add(const Duration(minutes: 5)), '$key india juliet'),
      ],
      [cap(b.add(const Duration(minutes: 4)), key)],
    );
    // Unclamped, x sits at 90/100 of its bucket (11:04:30), after y's match.
    expect(marks[2].source, MarkSource.captionMatch);
    expect(marks[2].wallClock, b.add(const Duration(minutes: 4)));
    expect(marks[1].source, MarkSource.interpolated);
    expect(marks[1].wallClock, b.add(const Duration(minutes: 4)));
    expect(marks[0].wallClock, b);
  });

  test('a match is never searched for before the previous match', () {
    final b = local('11:00:00');
    const first = 'one two three four five six seven eight';
    const second = 'alpha bravo charlie delta echo foxtrot golf hotel';
    final marks = alignSpeeches(
      [speech(b, first), speech(b, second)],
      [
        // The second speech's words also occur before the first match.
        cap(b.add(const Duration(seconds: 10)), second),
        cap(b.add(const Duration(seconds: 60)), first),
        cap(b.add(const Duration(seconds: 90)), second),
      ],
    );
    expect(marks[0].wallClock, b.add(const Duration(seconds: 60)));
    expect(marks[1].source, MarkSource.captionMatch);
    expect(marks[1].wallClock, b.add(const Duration(seconds: 90)));
  });

  test('short speeches are not matched', () {
    final b = local('11:00:00');
    expect(
      alignSpeeches(
        [speech(b, 'I have a point of order')],
        [cap(b, 'I have a point of order')],
      ).single.source,
      MarkSource.interpolated,
    );
  });

  test('matches seven ETHI caption anchors', () {
    final speeches = parseSpeechPageForTest(
      File('test/fixtures/op_speeches_ethi49_p1.json').readAsStringSync(),
      File('test/fixtures/op_speeches_ethi49_p2.json').readAsStringSync(),
    );
    final html = File('test/fixtures/event_ethi49_45680.html')
        .readAsStringSync();
    final raw = RegExp(r'\tccItems:(.*?),\r?\n').firstMatch(html)!.group(1)!;
    final items = ((jsonDecode(raw) as Map)['en'] as List)
        .map((e) => cap(parliamentTime(e['Begin']), e['Content'].trim()))
        .toList();
    final marks = alignSpeeches(speeches, items);
    const expected = {
      10: '11:05:00.468',
      22: '11:06:10.071',
      27: '11:16:13.507',
      41: '11:18:56.637',
      42: '11:18:58.839',
      51: '11:58:19.431',
      55: '12:10:48.379',
    };
    for (final e in expected.entries) {
      expect(marks[e.key].source, MarkSource.captionMatch);
    }
    for (final e in expected.entries) {
      expect(
        marks[e.key].wallClock.difference(local(e.value)).inSeconds.abs(),
        lessThanOrEqualTo(5),
      );
    }
    print(
      'captionMatch: ${marks.where((m) => m.source == MarkSource.captionMatch).length}, interpolated: ${marks.where((m) => m.source == MarkSource.interpolated).length}',
    );
  });

  test(
    'window prevents the repeated opening from pulling speech 6 forward',
    () {
      final speeches = parseSpeechPageForTest(
        File('test/fixtures/op_speeches_ethi49_p1.json').readAsStringSync(),
        File('test/fixtures/op_speeches_ethi49_p2.json').readAsStringSync(),
      );
      final html = File('test/fixtures/event_ethi49_45680.html')
          .readAsStringSync();
      final raw = RegExp(r'\tccItems:(.*?),\r?\n').firstMatch(html)!.group(1)!;
      final captions = ((jsonDecode(raw) as Map)['en'] as List)
          .map((e) => cap(parliamentTime(e['Begin']), e['Content'].trim()))
          .toList();
      List<String> normal(String text) =>
          RegExp(r"[a-z0-9']+")
              .allMatches(text.toLowerCase())
              .map((m) => m.group(0)!)
              .toList();
      final key = normal(speeches[6].textEn).take(8).toList();
      final stream = <({String word, DateTime time})>[];
      for (final caption in captions) {
        for (final word in normal(caption.text)) {
          stream.add((word: word, time: caption.begin));
        }
      }
      final repeatedAtLaterTime = <int>[];
      for (var p = 0; p < stream.length; p++) {
        var score = 0;
        for (var i = 0; i < key.length && p + i < stream.length; i++) {
          if (key[i] == stream[p + i].word) score++;
        }
        if (score >= 5 &&
            stream[p].time.difference(local('11:16:13.507')).inSeconds.abs() <=
                5) {
          repeatedAtLaterTime.add(p);
        }
      }
      expect(repeatedAtLaterTime, isNotEmpty);
      final marks = alignSpeeches(speeches, captions);
      expect(marks[6].wallClock.isBefore(local('11:10:00')), isTrue);
      for (var i = 1; i < marks.length; i++) {
        expect(marks[i].wallClock.isBefore(marks[i - 1].wallClock), isFalse);
      }
    },
  );
}

List<Speech> parseSpeechPageForTest(String a, String b) => [
  ...parseSpeechPage(a).speeches,
  ...parseSpeechPage(b).speeches,
];
