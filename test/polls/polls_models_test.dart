import 'package:flutter_test/flutter_test.dart';
import 'package:partake/polls/polls_models.dart';

import 'polls_seams.dart';

void main() {
  test('1. Every HTTP response seam parses, including integer shares', () {
    final summary = PollsSummary.fromJson(pollsSeam('summary'));
    expect(summary.asOf, DateTime(2026, 10, 12));
    expect(summary.seatsTotal, 343);
    expect(summary.seats, hasLength(6));
    expect(summary.average, hasLength(8));
    expect(summary.history, hasLength(4));
    expect(summary.majority!['LPC'], .91);
    expect(summary.minority!['LPC'], .08);
    expect(summary.comparison!.seats['LPC'], 205);
    expect(summary.note!.weekOf, '2026-10-05');
    final page = PollsPage.fromJson(pollsSeam('list'));
    expect(page.polls.single.shares['LPC'], 49.0);
    expect(page.polls.single.rolling, .25);
    expect(page.next, 'cursor-2026-10-02');
    expect(page.source.name, '338Canada');
    final leaders = LeaderPolls.fromJson(pollsSeam('leaders'));
    expect(leaders.bestPm.single.shares['Carney'], 46.0);
    expect(leaders.approval.single.approve, 55.0);
    expect(leaders.source.licence, 'CC BY-SA 4.0');
    final ridings = (pollsSeam('ridings')['ridings'] as List)
        .map((r) => RidingSummary.fromJson(r))
        .toList();
    expect(ridings, hasLength(3));
    expect(ridings.singleWhere((r) => r.id == '24038').mp!.personId, '123447');
    expect(ridings.first.mp, isNull);
    expect(ridings.first.projected, isNull);
    expect(ridings.first.winProb, isNull);
    final riding = RidingDetail.fromJson(pollsSeam('riding'));
    expect(riding.results2025['LPC'], 38.2);
    expect(riding.projection['LPC'], 47.2);
    expect(riding.history, hasLength(4));
    expect(riding.history.first.shares, hasLength(6));
    expect(() => summary.average['CAN']!['LPC'] = 1, throwsUnsupportedError);
    expect(() => page.polls.clear(), throwsUnsupportedError);
    expect(Party.values.map((p) => p.code), [
      'LPC',
      'CPC',
      'NDP',
      'BQ',
      'GPC',
      'OTH',
    ]);
  });

  test('1. P2 nulls and omitted history parse', () {
    final json = p2SummarySeam();
    final summary = PollsSummary.fromJson(json);
    expect(summary.majority, isNull);
    expect(summary.minority, isNull);
    expect(summary.comparison, isNull);
    expect(summary.note, isNull);
    for (final range in summary.seats.values) {
      expect(range.low, range.median);
      expect(range.high, range.median);
    }
    json.remove('history');
    expect(PollsSummary.fromJson(json).history, isEmpty);
  });
}
