import 'package:flutter/foundation.dart';

import 'watch_feed.dart';

/// `yyyy-mm-dd` as UTC midnight, the same shape `parliamentDate` gives.
DateTime _day(String date) {
  final parts = date.split('-').map(int.parse).toList();
  return DateTime.utc(parts[0], parts[1], parts[2]);
}

/// One row of `GET /watch/api/digests`, newest first.
@immutable
class WatchDigestSummary {
  const WatchDigestSummary({
    required this.id,
    required this.date,
    required this.kind,
    required this.createdAt,
    required this.replaces,
    required this.items,
  });
  final String id;

  /// The sitting day the digest covers (Ottawa date, UTC midnight).
  final DateTime date;

  /// `evening` or `morning`.
  final String kind;
  final DateTime createdAt;

  /// Set on a morning digest that replaces an evening one.
  final String? replaces;

  /// Distinct items in the digest.
  final int items;

  factory WatchDigestSummary.fromJson(Map<String, dynamic> json) =>
      WatchDigestSummary(
        id: json['id'] as String,
        date: _day(json['date'] as String),
        kind: json['kind'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        replaces: json['replaces'] as String?,
        items: json['items'] as int,
      );
}

/// One follow's part of a digest, oldest item first.
@immutable
class WatchDigestSection {
  const WatchDigestSection({
    required this.followId,
    required this.label,
    required this.items,
  });
  final String followId;
  final String label;
  final List<WatchFeedItem> items;

  factory WatchDigestSection.fromJson(Map<String, dynamic> json) =>
      WatchDigestSection(
        followId: json['follow']['id'] as String,
        label: json['follow']['label'] as String,
        items: [
          for (final item in json['items'] as List)
            WatchFeedItem.fromJson(item),
        ],
      );
}

/// `GET /watch/api/digests/<id>`.
@immutable
class WatchDigest {
  const WatchDigest({
    required this.id,
    required this.date,
    required this.kind,
    required this.replaces,
    required this.sections,
    this.opinion,
  });
  final String id;
  final DateTime date;
  final String kind;
  final String? replaces;
  final List<WatchDigestSection> sections;
  final String? opinion;

  factory WatchDigest.fromJson(Map<String, dynamic> json) => WatchDigest(
    id: json['id'] as String,
    date: _day(json['date'] as String),
    kind: json['kind'] as String,
    replaces: json['replaces'] as String?,
    opinion: json['opinion']?['text'] as String?,
    sections: [
      for (final section in json['sections'] as List)
        WatchDigestSection.fromJson(section),
    ],
  );
}

/// One row of `GET /watch/api/live`: an event being recorded now.
@immutable
class WatchLive {
  const WatchLive({
    required this.event,
    required this.title,
    required this.kind,
    required this.speaker,
    required this.lastLineAt,
    required this.business,
  });
  final String event;
  final String title;

  /// `house` or `committee`.
  final String kind;

  /// The guess on the newest caption line; null when there is none.
  final WatchSpeaker? speaker;
  final DateTime lastLineAt;
  final String? business;

  factory WatchLive.fromJson(Map<String, dynamic> json) => WatchLive(
    event: json['event'] as String,
    title: json['title'] as String,
    kind: json['kind'] as String,
    speaker: json['speaker'] == null
        ? null
        : WatchSpeaker.fromJson(json['speaker']),
    lastLineAt: DateTime.parse(json['last_line_at'] as String),
    business: json['business'] as String?,
  );
}
