import 'package:flutter/foundation.dart';

/// One page of `GET /watch/api/feed`; [next] is the cursor for the page after.
@immutable
class WatchFeedPage {
  const WatchFeedPage({required this.items, required this.next});
  final List<WatchFeedItem> items;
  final String? next;

  factory WatchFeedPage.fromJson(Map<String, dynamic> json) => WatchFeedPage(
    items: [
      for (final item in json['items'] as List) WatchFeedItem.fromJson(item),
    ],
    next: json['next'] as String?,
  );
}

@immutable
class WatchFeedFollow {
  const WatchFeedFollow({required this.id, required this.score});
  final String id;
  final double score;

  factory WatchFeedFollow.fromJson(Map<String, dynamic> json) =>
      WatchFeedFollow(
        id: json['id'] as String,
        score: (json['score'] as num).toDouble(),
      );
}

@immutable
class WatchFeedItem {
  const WatchFeedItem({
    required this.id,
    required this.kind,
    required this.at,
    required this.follows,
    required this.source,
    required this.superseded,
    required this.title,
    required this.text,
    required this.lang,
    required this.links,
    this.speaker,
    this.video,
    this.division,
    this.billStage,
  });
  final String id;

  /// `speech`, `division` or `bill_stage`; other values are kept as they come.
  final String kind;
  final DateTime at;
  final List<WatchFeedFollow> follows;
  final String source;
  final bool superseded;
  final String title;
  final String text;
  final String lang;
  final WatchSpeaker? speaker;

  /// Always null until Phase 2; kept raw so the shape can arrive unchanged.
  final Map<String, Object?>? video;
  final WatchFeedLinks links;
  final WatchDivision? division;
  final WatchBillStage? billStage;

  factory WatchFeedItem.fromJson(Map<String, dynamic> json) => WatchFeedItem(
    id: json['id'] as String,
    kind: json['kind'] as String,
    at: DateTime.parse(json['at'] as String),
    follows: [
      for (final follow in json['follows'] as List)
        WatchFeedFollow.fromJson(follow),
    ],
    source: json['source'] as String,
    superseded: json['superseded'] as bool,
    title: json['title'] as String,
    text: json['text'] as String,
    lang: json['lang'] as String,
    speaker: json['speaker'] == null
        ? null
        : WatchSpeaker.fromJson(json['speaker']),
    video: json['video'] as Map<String, Object?>?,
    links: WatchFeedLinks.fromJson(json['links']),
    division: json['division'] == null
        ? null
        : WatchDivision.fromJson(json['division']),
    billStage: json['bill_stage'] == null
        ? null
        : WatchBillStage.fromJson(json['bill_stage']),
  );
}

@immutable
class WatchSpeaker {
  const WatchSpeaker({
    required this.personId,
    required this.name,
    required this.party,
    required this.confidence,
    required this.from,
  });
  final String? personId;
  final String name;
  final String? party;
  final double confidence;
  final String from;

  factory WatchSpeaker.fromJson(Map<String, dynamic> json) => WatchSpeaker(
    personId: json['person_id'] as String?,
    name: json['name'] as String,
    party: json['party'] as String?,
    confidence: (json['confidence'] as num).toDouble(),
    from: json['from'] as String,
  );
}

@immutable
class WatchFeedLinks {
  const WatchFeedLinks({this.hansard, this.legisinfo, this.division});
  final String? hansard;
  final String? legisinfo;
  final String? division;

  factory WatchFeedLinks.fromJson(Map<String, dynamic> json) => WatchFeedLinks(
    hansard: json['hansard'] as String?,
    legisinfo: json['legisinfo'] as String?,
    division: json['division'] as String?,
  );
}

@immutable
class WatchDivision {
  const WatchDivision({
    required this.id,
    required this.number,
    required this.bill,
    required this.description,
    required this.result,
    required this.yeas,
    required this.nays,
    required this.paired,
    required this.parties,
    required this.mps,
  });
  final String id;
  final int number;
  final String? bill;
  final String description;

  /// `agreed`, `negatived` or `tie`; other values are kept as they come.
  final String result;
  final int yeas;
  final int nays;
  final int paired;
  final List<WatchDivisionParty> parties;

  /// Only the followed MPs.
  final List<WatchDivisionMp> mps;

  factory WatchDivision.fromJson(Map<String, dynamic> json) => WatchDivision(
    id: json['id'] as String,
    number: json['number'] as int,
    bill: json['bill'] as String?,
    description: json['description'] as String,
    result: json['result'] as String,
    yeas: json['yeas'] as int,
    nays: json['nays'] as int,
    paired: json['paired'] as int,
    parties: [
      for (final party in json['parties'] as List)
        WatchDivisionParty.fromJson(party),
    ],
    mps: [for (final mp in json['mps'] as List) WatchDivisionMp.fromJson(mp)],
  );
}

@immutable
class WatchDivisionParty {
  const WatchDivisionParty({
    required this.party,
    required this.yea,
    required this.nay,
    required this.split,
  });
  final String party;
  final int yea;
  final int nay;
  final bool split;

  factory WatchDivisionParty.fromJson(Map<String, dynamic> json) =>
      WatchDivisionParty(
        party: json['party'] as String,
        yea: json['yea'] as int,
        nay: json['nay'] as int,
        split: json['split'] as bool,
      );
}

@immutable
class WatchDivisionMp {
  const WatchDivisionMp({required this.personId, required this.vote});
  final String personId;

  /// `yea`, `nay` or `paired`.
  final String vote;

  factory WatchDivisionMp.fromJson(Map<String, dynamic> json) =>
      WatchDivisionMp(
        personId: json['person_id'] as String,
        vote: json['vote'] as String,
      );
}

@immutable
class WatchBillStage {
  const WatchBillStage({
    required this.bill,
    required this.number,
    required this.stage,
    required this.chamber,
    required this.at,
  });
  final String bill;
  final String number;
  final String stage;

  /// `house` or `senate`.
  final String chamber;
  final DateTime at;

  factory WatchBillStage.fromJson(Map<String, dynamic> json) => WatchBillStage(
    bill: json['bill'] as String,
    number: json['number'] as String,
    stage: json['stage'] as String,
    chamber: json['chamber'] as String,
    at: DateTime.parse(json['at'] as String),
  );
}
