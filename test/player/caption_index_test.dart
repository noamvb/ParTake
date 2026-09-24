import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:parlvu/parlvu.dart';
import 'package:partake/player/caption_index.dart';

void main() {
  final detail = parseEventPage(
    File('packages/parlvu/test/fixtures/event_fewo_13596766.html')
        .readAsStringSync(),
    id: 45750,
  );
  final captions = detail.captions[AudioLanguage.english]!;
  test('at finds FEWO caption and returns null outside its interval', () {
    final index = CaptionIndex(captions);
    expect(
      index.at(parliamentTime('2026-09-23T16:30:44'))!.text,
      '>> Voice of Interpreter: Welcome',
    );
    expect(
      index.at(captions.first.begin.subtract(const Duration(hours: 1))),
      isNull,
    );
    final linger = CaptionIndex([captions.first]);
    expect(
      linger.at(captions.first.end.add(const Duration(seconds: 1))),
      captions.first,
    );
    expect(
      linger.at(captions.first.end.add(const Duration(seconds: 2))),
      isNull,
    );
  });
  test('search matches case insensitive and adjacent captions, rejects short query', () {
    final index = CaptionIndex(captions);
    expect(index.search('welcome').map((h) => h.index), contains(0));
    expect(index.search('w'), isEmpty);
    expect(
      index.search('Welcome to the 47th').map((h) => h.index),
      contains(0),
    );
  });
}
