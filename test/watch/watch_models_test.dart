import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:partake/watch/watch_models.dart';

const seam = r'''{"version": 1, "follows": [
 {"id": "f_abc234", "kind": "house", "label": "House of Commons (chamber)", "created_at": "2026-10-12T15:00:00Z", "topic": null, "bill": null, "mp": null, "votes": null, "committee": null},
 {"id": "f_def567", "kind": "committee", "label": "ETHI", "created_at": "2026-10-12T15:00:01Z", "topic": null, "bill": null, "mp": null, "votes": null, "committee": {"code": "ETHI"}},
 {"id": "f_ghi234", "kind": "topic", "label": "Housing affordability", "created_at": "2026-10-12T15:00:02Z", "topic": {"phrases": {"en": "housing affordability", "fr": "abordabilité du logement"}, "keywords": ["CMHC"], "threshold": 0.55}, "bill": null, "mp": null, "votes": null, "committee": null},
 {"id": "f_jkl567", "kind": "bill", "label": "C-37", "created_at": "2026-10-12T15:00:03Z", "topic": null, "bill": {"id": "45-1/C-37", "number": "C-37", "title": "First Nations Clean Water Act"}, "mp": null, "votes": null, "committee": null},
 {"id": "f_mno234", "kind": "mp", "label": "Billy Morin", "created_at": "2026-10-12T15:00:04Z", "topic": null, "bill": null, "mp": {"person_id": "123447", "name": "Billy Morin", "party": "Conservative", "riding": "Edmonton Northwest"}, "votes": null, "committee": null},
 {"id": "f_pqr567", "kind": "votes", "label": "Party splits", "created_at": "2026-10-12T15:00:05Z", "topic": null, "bill": null, "mp": null, "votes": {"filter": "party_split"}, "committee": null},
 {"id": "f_stu234", "kind": "pm-qp", "label": "Prime Minister at Question Period", "created_at": "2026-10-12T15:00:06Z", "topic": null, "bill": null, "mp": null, "votes": null, "committee": null}
]}''';

WatchFollowList seamList() => WatchFollowList.fromJson(jsonDecode(seam));

void main() {
  test('1 seam round-trips all seven kinds', () {
    final list = seamList();
    expect(list.version, 1);
    expect(list.follows, hasLength(7));
    expect(list.follows.map((f) => f.kind), [
      'house',
      'committee',
      'topic',
      'bill',
      'mp',
      'votes',
      'pm-qp',
    ]);
    final topic = list.follows[2].topic!;
    expect(topic.fr, 'abordabilité du logement');
    expect(topic.keywords, ['CMHC']);
    expect(topic.threshold, 0.55);
    expect(list.follows[4].mp!.personId, '123447');
    expect(list.follows[3].bill!.id, '45-1/C-37');
    expect(list.follows.first.createdAt, DateTime.utc(2026, 10, 12, 15));
    final original = jsonDecode(seam)['follows'] as List;
    for (var i = 0; i < 7; i++) {
      expect(jsonDecode(jsonEncode(list.follows[i].toJson())), original[i]);
    }
  });
  test('2 encoder emits exact votes JSON', () {
    expect(
      jsonEncode(
        WatchFollow(
          kind: 'votes',
          label: 'All votes',
          votesFilter: 'all',
        ).toJson(),
      ),
      '{"kind":"votes","label":"All votes","topic":null,"bill":null,"mp":null,"votes":{"filter":"all"},"committee":null}',
    );
  });
  test('3 legacy keys and labels round-trip', () {
    final labels = {
      'HOC': 'House of Commons (chamber)',
      'PM-QP': 'Prime Minister at Question Period',
      'ETHI': 'ETHI',
    };
    for (final entry in labels.entries) {
      final follow = legacyFollow(entry.key);
      expect(legacyKeyOf(follow), entry.key);
      expect(follow.label, entry.value);
    }
    for (final follow in seamList().follows.sublist(2, 6)) {
      expect(legacyKeyOf(follow), isNull);
    }
  });
}
