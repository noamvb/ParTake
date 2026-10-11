import 'package:flutter/foundation.dart';

@immutable
class WatchTopic {
  WatchTopic({
    required this.en,
    required this.fr,
    required List<String> keywords,
    required this.threshold,
  }) : keywords = List.unmodifiable(keywords);

  final String en;
  final String fr;
  final List<String> keywords;
  final double threshold;

  factory WatchTopic.fromJson(Map<String, dynamic> json) => WatchTopic(
    en: json['phrases']['en'] as String,
    fr: json['phrases']['fr'] as String,
    keywords: List<String>.from(json['keywords'] as List),
    threshold: (json['threshold'] as num).toDouble(),
  );

  Map<String, Object?> toJson() => {
    'phrases': {'en': en, 'fr': fr},
    'keywords': keywords,
    'threshold': threshold,
  };
}

@immutable
class WatchBillRef {
  const WatchBillRef({
    required this.id,
    required this.number,
    required this.title,
  });
  final String id;
  final String number;
  final String title;

  factory WatchBillRef.fromJson(Map<String, dynamic> json) => WatchBillRef(
    id: json['id'] as String,
    number: json['number'] as String,
    title: json['title'] as String,
  );
  Map<String, Object?> toJson() => {'id': id, 'number': number, 'title': title};
}

@immutable
class WatchMpRef {
  const WatchMpRef({
    required this.personId,
    required this.name,
    required this.party,
    required this.riding,
  });
  final String personId;
  final String name;
  final String party;
  final String riding;

  factory WatchMpRef.fromJson(Map<String, dynamic> json) => WatchMpRef(
    personId: json['person_id'] as String,
    name: json['name'] as String,
    party: json['party'] as String,
    riding: json['riding'] as String,
  );
  Map<String, Object?> toJson() => {
    'person_id': personId,
    'name': name,
    'party': party,
    'riding': riding,
  };
}

@immutable
class WatchFollow {
  const WatchFollow({
    this.id,
    required this.kind,
    required this.label,
    this.createdAt,
    this.topic,
    this.bill,
    this.mp,
    this.votesFilter,
    this.committeeCode,
  });
  final String? id;
  final String kind;
  final String label;
  final DateTime? createdAt;
  final WatchTopic? topic;
  final WatchBillRef? bill;
  final WatchMpRef? mp;
  final String? votesFilter;
  final String? committeeCode;

  factory WatchFollow.fromJson(Map<String, dynamic> json) => WatchFollow(
    id: json['id'] as String?,
    kind: json['kind'] as String,
    label: json['label'] as String,
    createdAt: json['created_at'] == null
        ? null
        : DateTime.parse(json['created_at'] as String),
    topic: json['topic'] == null ? null : WatchTopic.fromJson(json['topic']),
    bill: json['bill'] == null ? null : WatchBillRef.fromJson(json['bill']),
    mp: json['mp'] == null ? null : WatchMpRef.fromJson(json['mp']),
    votesFilter: json['votes']?['filter'] as String?,
    committeeCode: json['committee']?['code'] as String?,
  );

  Map<String, Object?> toJson() => {
    if (id != null) 'id': id,
    'kind': kind,
    'label': label,
    if (createdAt != null)
      'created_at': '${createdAt!.toUtc().toIso8601String().split('.').first}Z',
    'topic': topic?.toJson(),
    'bill': bill?.toJson(),
    'mp': mp?.toJson(),
    'votes': votesFilter == null ? null : {'filter': votesFilter},
    'committee': committeeCode == null ? null : {'code': committeeCode},
  };
}

@immutable
class WatchFollowList {
  WatchFollowList({required this.version, required List<WatchFollow> follows})
    : follows = List.unmodifiable(follows);
  final int version;
  final List<WatchFollow> follows;
  factory WatchFollowList.fromJson(Map<String, dynamic> json) =>
      WatchFollowList(
        version: json['version'] as int,
        follows: (json['follows'] as List)
            .map((f) => WatchFollow.fromJson(f))
            .toList(),
      );
  Map<String, Object?> toJson() => {
    'version': version,
    'follows': follows.map((f) => f.toJson()).toList(),
  };
}

@immutable
class WatchMember {
  const WatchMember({
    required this.personId,
    required this.name,
    required this.party,
    required this.riding,
    required this.province,
    this.role,
  });
  final String personId;
  final String name;
  final String party;
  final String riding;
  final String province;
  final String? role;
  factory WatchMember.fromJson(Map<String, dynamic> json) => WatchMember(
    personId: json['person_id'] as String,
    name: json['name'] as String,
    party: json['party'] as String,
    riding: json['riding'] as String,
    province: json['province'] as String,
    role: json['role'] as String?,
  );
  Map<String, Object?> toJson() => {
    'person_id': personId,
    'name': name,
    'party': party,
    'riding': riding,
    'province': province,
    'role': role,
  };
}

@immutable
class WatchBill {
  const WatchBill({
    required this.id,
    required this.number,
    required this.title,
    required this.stage,
    this.stageAt,
  });
  final String id;
  final String number;
  final String title;
  final String stage;
  final String? stageAt;
  factory WatchBill.fromJson(Map<String, dynamic> json) => WatchBill(
    id: json['id'] as String,
    number: json['number'] as String,
    title: json['title'] as String,
    stage: json['stage'] as String,
    stageAt: json['stage_at'] as String?,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'number': number,
    'title': title,
    'stage': stage,
    'stage_at': stageAt,
  };
}

String? legacyKeyOf(WatchFollow follow) => switch (follow.kind) {
  'house' => 'HOC',
  'pm-qp' => 'PM-QP',
  'committee' => follow.committeeCode,
  _ => null,
};

WatchFollow legacyFollow(String key) => switch (key) {
  'HOC' => const WatchFollow(
    kind: 'house',
    label: 'House of Commons (chamber)',
  ),
  'PM-QP' => const WatchFollow(
    kind: 'pm-qp',
    label: 'Prime Minister at Question Period',
  ),
  _ => WatchFollow(kind: 'committee', label: key, committeeCode: key),
};
