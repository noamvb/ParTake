import 'dart:io';

import 'package:parlvu/parlvu.dart';
import 'package:test/test.dart';

Speech speech(List<SpeechParagraph> paragraphs, {String text = ''}) => Speech(
  bucketTime: DateTime.utc(2026, 7, 7),
  speaker: 'A',
  politicianUrl: null,
  textEn: text,
  procedural: false,
  url: '/a/',
  paragraphs: paragraphs,
);

SpeakerMark mark(Speech speech, DateTime time) => SpeakerMark(
  speech: speech,
  wallClock: time,
  source: MarkSource.interpolated,
);

Caption caption(DateTime time, String text) =>
    Caption(begin: time, end: time.add(const Duration(seconds: 1)), text: text);

void main() {
  test('French marker produces the exact Floor switch time', () {
    final t0 = DateTime.utc(2026, 7, 7, 12);
    final marks = [
      mark(
        speech([
          const SpeechParagraph(
            language: AudioLanguage.english,
            textEn: 'one two',
            textFr: '',
          ),
        ]),
        t0,
      ),
      mark(
        speech([
          const SpeechParagraph(
            language: AudioLanguage.french,
            textEn: '',
            textFr: 'un deux',
          ),
        ]),
        t0.add(const Duration(seconds: 60)),
      ),
    ];
    final result = floorLanguageSwitches(marks, {
      AudioLanguage.english: [
        caption(t0.add(const Duration(seconds: 62)), '[Speaking in French]'),
      ],
    });
    expect(result.map((s) => (s.wallClock, s.language)), [
      (t0, AudioLanguage.english),
      (t0.add(const Duration(seconds: 62)), AudioLanguage.french),
    ]);
  });

  test('text alignment locates a mid-speech language change', () {
    final t0 = DateTime.utc(2026, 7, 7, 12);
    final m = mark(
      speech([
        const SpeechParagraph(
          language: AudioLanguage.french,
          textEn: '',
          textFr: 'un deux trois quatre cinq six sept huit neuf',
        ),
        const SpeechParagraph(
          language: AudioLanguage.english,
          textEn: 'alpha bravo charlie delta echo foxtrot golf hotel india',
          textFr: '',
        ),
      ]),
      t0,
    );
    final result = floorLanguageSwitches(
      [m],
      {
        AudioLanguage.english: [
          caption(
            t0.add(const Duration(seconds: 40)),
            'alpha bravo charlie delta echo foxtrot golf hotel',
          ),
        ],
      },
    );
    expect(result.last.wallClock, t0.add(const Duration(seconds: 40)));
    expect(result.last.language, AudioLanguage.english);
  });

  test('interpretation marker can beat the paragraph anchor', () {
    final t0 = DateTime.utc(2026, 7, 7, 12);
    final m = mark(
      speech([
        const SpeechParagraph(
          language: AudioLanguage.french,
          textEn: '',
          textFr: 'un deux trois quatre cinq six sept huit neuf',
        ),
        const SpeechParagraph(
          language: AudioLanguage.english,
          textEn: 'alpha bravo charlie delta echo foxtrot golf hotel india',
          textFr: '',
        ),
      ]),
      t0,
    );
    final result = floorLanguageSwitches(
      [m],
      {
        AudioLanguage.english: [
          caption(
            t0.add(const Duration(seconds: 25)),
            '[End of Interpretation]',
          ),
        ],
      },
    );
    expect(result.last.wallClock, t0.add(const Duration(seconds: 25)));
    expect(result.last.language, AudioLanguage.english);
  });

  test('floorLanguageAt uses the last switch at or before the instant', () {
    final t0 = DateTime.utc(2026, 7, 7, 12);
    final switches = [
      LanguageSwitch(t0, AudioLanguage.english),
      LanguageSwitch(t0.add(const Duration(seconds: 60)), AudioLanguage.french),
    ];
    expect(
      floorLanguageAt(switches, t0.subtract(const Duration(microseconds: 1))),
      isNull,
    );
    expect(floorLanguageAt(switches, t0), AudioLanguage.english);
    expect(
      floorLanguageAt(switches, t0.add(const Duration(seconds: 30))),
      AudioLanguage.english,
    );
    expect(
      floorLanguageAt(switches, t0.add(const Duration(seconds: 60))),
      AudioLanguage.french,
    );
  });

  test('ETHI 49 captions follow Floor language across both switches', () {
    final p1 = parseSpeechPage(
      File('test/fixtures/op_speeches_ethi49_p1.json').readAsStringSync(),
    );
    final p2 = parseSpeechPage(
      File('test/fixtures/op_speeches_ethi49_p2.json').readAsStringSync(),
    );
    final speeches = [...p1.speeches, ...p2.speeches];
    final detail = parseEventPage(
      File('test/fixtures/event_ethi49_45680.html').readAsStringSync(),
      id: 45680,
    );
    final marks = alignSpeeches(
      speeches,
      detail.captions[AudioLanguage.english] ?? const [],
    );
    final switches = floorLanguageSwitches(marks, detail.captions);
    final lapointeSwitch = switches.firstWhere(
      (s) =>
          s.language == AudioLanguage.french &&
          !s.wallClock.isBefore(parliamentTime('2026-07-07T11:15:00')) &&
          s.wallClock.isBefore(parliamentTime('2026-07-07T11:16:00')),
    );
    final chairSwitch = switches.firstWhere(
      (s) =>
          s.language == AudioLanguage.english &&
          !s.wallClock.isBefore(parliamentTime('2026-07-07T11:44:00')) &&
          s.wallClock.isBefore(parliamentTime('2026-07-07T11:45:00')),
    );
    // Real switch instants are asserted below; these are useful diagnostics if a rule regresses.
    print('Lapointe switch: ${lapointeSwitch.wallClock.toIso8601String()}');
    print('Chair switch: ${chairSwitch.wallClock.toIso8601String()}');
    expect(
      floorLanguageAt(switches, parliamentTime('2026-07-07T11:15:24')),
      AudioLanguage.english,
    );
    expect(
      floorLanguageAt(switches, parliamentTime('2026-07-07T11:15:36')),
      AudioLanguage.french,
    );
    expect(
      floorLanguageAt(switches, parliamentTime('2026-07-07T11:44:12')),
      AudioLanguage.french,
    );
    expect(
      floorLanguageAt(switches, parliamentTime('2026-07-07T11:44:22')),
      AudioLanguage.english,
    );
  });

  test('English captions alone find the Floor switches without Hansard', () {
    final t0 = DateTime.utc(2026, 7, 7, 12);
    final result = captionLanguageSwitches({
      AudioLanguage.english: [
        caption(t0, 'Good morning'),
        caption(t0.add(const Duration(seconds: 10)), '[Speaking in French]'),
        caption(t0.add(const Duration(seconds: 40)), '[End of Interpretation]'),
      ],
    });
    expect(result.map((s) => (s.wallClock, s.language)), [
      (t0, AudioLanguage.english),
      (t0.add(const Duration(seconds: 10)), AudioLanguage.french),
      (t0.add(const Duration(seconds: 40)), AudioLanguage.english),
    ]);
  });

  test('"[Speaking French]" without "in" switches the Floor to French', () {
    final t0 = DateTime.utc(2026, 7, 7, 12);
    final result = captionLanguageSwitches({
      AudioLanguage.english: [
        caption(t0, 'Good morning'),
        caption(t0.add(const Duration(seconds: 5)), '[Speaking French]'),
      ],
    });
    expect(result.map((s) => (s.wallClock, s.language)), [
      (t0, AudioLanguage.english),
      (t0.add(const Duration(seconds: 5)), AudioLanguage.french),
    ]);
  });

  test('"(Voice of the Interpreter)" switches the Floor to French', () {
    final t0 = DateTime.utc(2026, 7, 7, 12);
    final result = captionLanguageSwitches({
      AudioLanguage.english: [
        caption(t0, 'Good morning'),
        caption(
          t0.add(const Duration(seconds: 5)),
          '(Voice of the Interpreter)',
        ),
      ],
    });
    expect(result.map((s) => (s.wallClock, s.language)), [
      (t0, AudioLanguage.english),
      (t0.add(const Duration(seconds: 5)), AudioLanguage.french),
    ]);
  });

  test('French track alone yields the English switch at its marker', () {
    final t0 = DateTime.utc(2026, 7, 7, 12);
    final result = captionLanguageSwitches({
      AudioLanguage.french: [
        caption(t0, 'Bonjour'),
        caption(
          t0.add(const Duration(seconds: 20)),
          "(voix de l'interprète) Merci",
        ),
      ],
    });
    expect(result.map((s) => (s.wallClock, s.language)), [
      (t0.add(const Duration(seconds: 20)), AudioLanguage.english),
    ]);
  });

  test('captions without interpretation markers yield no Floor switches', () {
    final t0 = DateTime.utc(2026, 7, 7, 12);
    final result = captionLanguageSwitches({
      AudioLanguage.english: [caption(t0, 'Hello')],
      AudioLanguage.french: [caption(t0, 'Bonjour')],
    });
    expect(result, isEmpty);
  });

  test('ETHI 49 captions alone follow Floor language across both switches', () {
    final detail = parseEventPage(
      File('test/fixtures/event_ethi49_45680.html').readAsStringSync(),
      id: 45680,
    );
    final switches = captionLanguageSwitches(detail.captions);
    expect(
      floorLanguageAt(switches, parliamentTime('2026-07-07T11:15:24')),
      AudioLanguage.english,
    );
    expect(
      floorLanguageAt(switches, parliamentTime('2026-07-07T11:15:36')),
      AudioLanguage.french,
    );
    expect(
      floorLanguageAt(switches, parliamentTime('2026-07-07T11:44:12')),
      AudioLanguage.french,
    );
    expect(
      floorLanguageAt(switches, parliamentTime('2026-07-07T11:44:22')),
      AudioLanguage.english,
    );
  });

  test(
    'a switch reversed within three seconds is caption lag, not a speaker',
    () {
      final t0 = DateTime.utc(2026, 10, 7, 18);
      DateTime at(int seconds) => t0.add(Duration(seconds: seconds));
      final result = captionLanguageSwitches({
        AudioLanguage.english: [
          caption(at(0), 'Thank you, Mr. Speaker.'),
          caption(at(10), '[ Speaking French ]'),
          caption(at(40), '[ End of Interpretation ]'),
          caption(at(41), '>> Voice of Interpreter:'),
          caption(at(80), '[ Speaking French ]'),
          caption(at(82), '[ End of Interpretation ]'),
        ],
        AudioLanguage.french: [caption(at(41), "- (voix de l'interprète) Je")],
      });
      expect(result.map((s) => (s.wallClock, s.language)), [
        (at(0), AudioLanguage.english),
        (at(10), AudioLanguage.french),
        (at(41), AudioLanguage.english),
      ]);
    },
  );
}
