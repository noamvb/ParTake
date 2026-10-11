import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:partake/watch/watch_digests.dart';

final _digests = File('test/watch/digests_seam.json').readAsStringSync();
final _digest = File('test/watch/digest_seam.json').readAsStringSync();
final _live = File('test/watch/live_seam.json').readAsStringSync();

void main() {
  test(
    '1 digests seam parses two rows with ids, kinds, items and replaces',
    () {
      final rows = [
        for (final row in jsonDecode(_digests) as List)
          WatchDigestSummary.fromJson(row),
      ];
      expect(rows, hasLength(2));

      expect(rows[0].id, 'd_2026-10-19_morning');
      expect(rows[0].date, DateTime.utc(2026, 10, 19));
      expect(rows[0].kind, 'morning');
      expect(rows[0].createdAt, DateTime.utc(2026, 10, 20, 11, 5));
      expect(rows[0].replaces, 'd_2026-10-19_evening');
      expect(rows[0].items, 2);

      expect(rows[1].id, 'd_2026-10-19_evening');
      expect(rows[1].kind, 'evening');
      expect(rows[1].replaces, isNull);
      expect(rows[1].items, 1);
    },
  );
  test(
    '2 digest seam parses the section, the captioned item and its video',
    () {
      final digest = WatchDigest.fromJson(jsonDecode(_digest));
      expect(digest.id, 'd_2026-10-19_evening');
      expect(digest.date, DateTime.utc(2026, 10, 19));
      expect(digest.kind, 'evening');
      expect(digest.replaces, isNull);

      expect(digest.sections, hasLength(1));
      final section = digest.sections.single;
      expect(section.followId, 'f_jkl567');
      expect(section.label, 'Bill C-37');

      final item = section.items.single;
      expect(item.source, 'captions');
      expect(item.video!.event, '45873');
      expect(item.video!.at, DateTime.utc(2026, 10, 19, 15, 31, 12, 400));
      expect(item.video!.offsetS, 1872.4);
      expect(item.speaker!.from, 'caption_call');
      expect(item.speaker!.confidence, 0.85);
    },
  );
  test('3 live seam parses the row and an empty list parses to nothing', () {
    final rows = [
      for (final row in jsonDecode(_live) as List) WatchLive.fromJson(row),
    ];
    expect(rows, hasLength(1));
    expect(rows.single.event, '45873');
    expect(rows.single.title, 'House of Commons, sitting 150');
    expect(rows.single.kind, 'house');
    expect(rows.single.speaker!.name, 'Mandy Gull-Masty');
    expect(rows.single.speaker!.from, 'caption_call');
    expect(rows.single.lastLineAt, DateTime.utc(2026, 10, 19, 15, 31, 40, 120));
    expect(rows.single.business, isNull);

    final none = [
      for (final row in jsonDecode('[]') as List) WatchLive.fromJson(row),
    ];
    expect(none, isEmpty);
  });
}
