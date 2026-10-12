import 'package:flutter/material.dart';

Map<String, double> _numbers(dynamic json) => Map.unmodifiable(
  (json as Map<String, dynamic>).map(
    (key, value) => MapEntry(key, (value as num).toDouble()),
  ),
);

/// Display order and colours are shared by every polls view.
enum Party {
  lpc('LPC', Color(0xFFD71920)),
  cpc('CPC', Color(0xFF1A4782)),
  ndp('NDP', Color(0xFFF37021)),
  bq('BQ', Color(0xFF33B2CC)),
  gpc('GPC', Color(0xFF3D9B35)),
  oth('OTH', Color(0xFF9E9E9E));

  const Party(this.code, this.color);
  final String code;
  final Color color;
  static Party fromCode(String code) =>
      values.firstWhere((p) => p.code == code, orElse: () => oth);
}

@immutable
class PollsSource {
  const PollsSource(this.name, this.url, this.fetchedAt, this.licence);
  final String name, url, fetchedAt;
  final String? licence;
  factory PollsSource.fromJson(Map<String, dynamic> j) => PollsSource(
    j['name'] as String,
    j['url'] as String,
    j['fetched_at'] as String,
    j['licence'] as String?,
  );
}

@immutable
class PollsPoll {
  PollsPoll.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      firm = j['firm'] as String,
      endDate = j['end_date'] as String,
      sample = (j['sample'] as num).toInt(),
      rolling = (j['rolling'] as num).toDouble(),
      link = j['link'] as String,
      region = j['region'] as String,
      shares = _numbers(j['shares']);
  final String id, firm, endDate, link, region;
  final int sample;
  final double rolling;
  final Map<String, double> shares;
}

@immutable
class PollsPage {
  PollsPage.fromJson(Map<String, dynamic> j)
    : polls = List.unmodifiable(
        (j['polls'] as List).map((p) => PollsPoll.fromJson(p)),
      ),
      next = j['next'] as String?,
      source = PollsSource.fromJson(j['source']);
  final List<PollsPoll> polls;
  final String? next;
  final PollsSource source;
}

@immutable
class SeatRange {
  SeatRange.fromJson(Map<String, dynamic> j)
    : median = (j['median'] as num).toInt(),
      low = (j['low'] as num).toInt(),
      high = (j['high'] as num).toInt();
  final int median, low, high;
}

@immutable
class PollsComparison {
  PollsComparison.fromJson(Map<String, dynamic> j)
    : name = j['name'] as String,
      asOf = j['as_of'] as String,
      seats = _numbers(j['seats']);
  final String name, asOf;
  final Map<String, double> seats;
}

@immutable
class PollsNote {
  PollsNote.fromJson(Map<String, dynamic> j)
    : weekOf = j['week_of'] as String,
      text = j['text'] as String;
  final String weekOf, text;
}

@immutable
class PollsHistory {
  PollsHistory.fromJson(Map<String, dynamic> j)
    : date = DateTime.parse(j['date'] as String),
      average = _numbers(j['average']),
      seats = _numbers(j['seats']);
  final DateTime date;
  final Map<String, double> average, seats;
}

@immutable
class PollsSummary {
  PollsSummary.fromJson(Map<String, dynamic> j)
    : asOf = DateTime.parse(j['as_of'] as String),
      pollsUsed = (j['polls_used'] as num).toInt(),
      average = Map.unmodifiable(
        (j['average'] as Map<String, dynamic>).map(
          (k, v) => MapEntry(k, _numbers(v)),
        ),
      ),
      seats = Map.unmodifiable(
        (j['seats'] as Map<String, dynamic>).map(
          (k, v) => MapEntry(k, SeatRange.fromJson(v)),
        ),
      ),
      majority = j['majority'] == null ? null : _numbers(j['majority']),
      minority = j['minority'] == null ? null : _numbers(j['minority']),
      seatsTotal = (j['seats_total'] as num).toInt(),
      majorityLine = (j['majority_line'] as num).toInt(),
      comparison = j['comparison'] == null
          ? null
          : PollsComparison.fromJson(j['comparison']),
      note = j['note'] == null ? null : PollsNote.fromJson(j['note']),
      history = List.unmodifiable(
        ((j['history'] as List?) ?? []).map((h) => PollsHistory.fromJson(h)),
      );
  final DateTime asOf;
  final int pollsUsed, seatsTotal, majorityLine;
  final Map<String, Map<String, double>> average;
  final Map<String, SeatRange> seats;
  final Map<String, double>? majority, minority;
  final PollsComparison? comparison;
  final PollsNote? note;
  final List<PollsHistory> history;
}

@immutable
class BestPmPoll {
  BestPmPoll.fromJson(Map<String, dynamic> j)
    : firm = j['firm'] as String,
      endDate = j['end_date'] as String,
      shares = _numbers(j['shares']);
  final String firm, endDate;
  final Map<String, double> shares;
}

@immutable
class ApprovalPoll {
  ApprovalPoll.fromJson(Map<String, dynamic> j)
    : firm = j['firm'] as String,
      endDate = j['end_date'] as String,
      approve = (j['approve'] as num).toDouble(),
      disapprove = (j['disapprove'] as num).toDouble();
  final String firm, endDate;
  final double approve, disapprove;
}

@immutable
class LeaderPolls {
  LeaderPolls.fromJson(Map<String, dynamic> j)
    : bestPm = List.unmodifiable(
        (j['best_pm'] as List).map((p) => BestPmPoll.fromJson(p)),
      ),
      approval = List.unmodifiable(
        (j['approval'] as List).map((p) => ApprovalPoll.fromJson(p)),
      ),
      source = PollsSource.fromJson(j['source']);
  final List<BestPmPoll> bestPm;
  final List<ApprovalPoll> approval;
  final PollsSource source;
}

@immutable
class RidingMp {
  RidingMp.fromJson(Map<String, dynamic> j)
    : personId = j['person_id'] as String,
      name = j['name'] as String,
      party = j['party'] as String;
  final String personId, name, party;
}

@immutable
class RidingSummary {
  RidingSummary.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      name = j['name'] as String,
      province = j['province'] as String,
      region = j['region'] as String,
      mp = j['mp'] == null ? null : RidingMp.fromJson(j['mp']),
      won2025 = j['won_2025'] as String,
      projected = j['projected'] as String?,
      winProb = (j['win_prob'] as num?)?.toDouble(),
      status = j['status'] as String;
  final String id, name, province, region, won2025, status;
  final String? projected;
  final RidingMp? mp;
  final double? winProb;
}

@immutable
class RidingHistory {
  RidingHistory.fromJson(Map<String, dynamic> j)
    : date = DateTime.parse(j['date'] as String),
      shares = _numbers(j['shares']);
  final DateTime date;
  final Map<String, double> shares;
}

@immutable
class RidingDetail extends RidingSummary {
  RidingDetail.fromJson(super.j)
    : results2025 = _numbers(j['results_2025']),
      projection = _numbers(j['projection']),
      history = List.unmodifiable(
        (j['history'] as List).map((h) => RidingHistory.fromJson(h)),
      ),
      super.fromJson();
  final Map<String, double> results2025, projection;
  final List<RidingHistory> history;
}
