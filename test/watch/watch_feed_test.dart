import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:partake/watch/watch_feed.dart';

final _seam = File('test/watch/feed_seam.json').readAsStringSync();

void main() {
  test('1 feed seam parses four items and the fields the screen needs', () {
    final page = WatchFeedPage.fromJson(jsonDecode(_seam));
    expect(page.items, hasLength(4));
    expect(page.next, isNull);

    final speech = page.items[1];
    expect(speech.speaker!.name, 'Mandy Gull-Masty');
    expect(speech.speaker!.party, 'Liberal');

    final division = page.items[2].division!;
    expect(division.nays, 2);
    expect(division.parties, hasLength(2));
    expect(division.mps.single.personId, '123447');
    expect(division.mps.single.vote, 'nay');

    final evidence = page.items[3];
    expect(evidence.speaker!.personId, isNull);
    expect(evidence.lang, 'fr');

    expect(page.items[0].billStage!.chamber, 'house');
    expect(page.items[0].at, DateTime.utc(2026, 10, 9, 17, 20, 48));
  });
  test('2 unknown kind and extra keys parse without throwing', () {
    final item = {
      'id': 'm_x_1',
      'kind': 'future_kind',
      'at': '2026-10-09T14:00:00Z',
      'follows': [],
      'source': 'hansard',
      'superseded': false,
      'title': 'Something new',
      'text': 'Body',
      'lang': 'en',
      'speaker': null,
      'video': null,
      'links': {'hansard': null, 'legisinfo': null, 'division': null},
      'division': null,
      'bill_stage': null,
      'brand_new_key': {'anything': true},
    };
    final page = WatchFeedPage.fromJson({
      'items': [item],
      'next': 'c_1',
      'extra_page_key': 1,
    });
    expect(page.items.single.kind, 'future_kind');
    expect(page.items.single.title, 'Something new');
    expect(page.items.single.speaker, isNull);
    expect(page.next, 'c_1');
  });
}
