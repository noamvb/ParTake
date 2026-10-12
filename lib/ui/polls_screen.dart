import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../polls/polls_client.dart';
import '../polls/polls_models.dart';
import '../watch/watch_client.dart';
import 'riding_screen.dart';
import 'polls_method_screen.dart';

String _date(DateTime date) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${days[date.weekday - 1]} ${date.day} ${months[date.month - 1]}';
}

class PollsScreen extends StatefulWidget {
  const PollsScreen({super.key, required this.polls, this.openLink});
  final PollsClient polls;
  final Future<bool> Function(Uri)? openLink;
  @override
  State<PollsScreen> createState() => _PollsScreenState();
}

class _PollsScreenState extends State<PollsScreen> {
  PollsSummary? _summary;
  LeaderPolls? _leaders;
  final _polls = <PollsPoll>[];
  String? _next;
  Object? _summaryError, _leadersError, _listError;
  bool _summaryLoading = true, _leadersLoading = true, _listLoading = true;
  bool _moreLoading = false;
  String _region = 'CAN';
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    final generation = ++_generation;
    setState(() {
      _summaryLoading = _leadersLoading = _listLoading = true;
      _summaryError = _leadersError = _listError = null;
      _moreLoading = false;
    });
    await Future.wait([
      _loadSummary(generation),
      _loadLeaders(generation),
      _loadList(generation),
    ]);
  }

  Future<void> _loadSummary(int generation) async {
    try {
      final data = await widget.polls.summary();
      if (mounted && generation == _generation) setState(() => _summary = data);
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _summaryError = error);
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _summaryLoading = false);
      }
    }
  }

  Future<void> _loadLeaders(int generation) async {
    try {
      final data = await widget.polls.leaders();
      if (mounted && generation == _generation) setState(() => _leaders = data);
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _leadersError = error);
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _leadersLoading = false);
      }
    }
  }

  Future<void> _loadList(int generation, {String? before}) async {
    try {
      final page = await widget.polls.list(before: before);
      if (mounted && generation == _generation) {
        setState(() {
          if (before == null) _polls.clear();
          _polls.addAll(page.polls);
          _next = page.next;
          _listError = null;
        });
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _listError = error);
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _listLoading = false;
          _moreLoading = false;
        });
      }
    }
  }

  Widget _failure(Object error, VoidCallback retry) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(pollsError(error)),
      TextButton(onPressed: retry, child: const Text('Retry')),
    ],
  );

  void _method([String? section]) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PollsMethodScreen(section: section),
    ),
  );

  Widget _heading(String text, {String? tooltip, String? section}) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 8),
    child: Row(
      children: [
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.titleLarge),
        ),
        if (tooltip != null)
          IconButton(
            tooltip: tooltip,
            icon: const Icon(Icons.info_outline),
            onPressed: () => _method(section),
          ),
      ],
    ),
  );

  List<Widget> _projection(PollsSummary s) {
    final parties =
        Party.values.where((p) => (s.seats[p.code]?.median ?? 0) > 0).toList()
          ..sort(
            (a, b) =>
                s.seats[b.code]!.median.compareTo(s.seats[a.code]!.median),
          );
    final comparison = s.comparison;
    final note = s.note;
    final history = s.history.toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final latest = history.isEmpty
        ? s.average['CAN'] ?? <String, double>{}
        : history.last.average;
    return [
      _heading('Projection, ${_date(s.asOf)}'),
      Text('${s.pollsUsed} polls'),
      const Text('A snapshot if an election were held today, not a forecast.'),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: _method,
          child: const Text('How this works'),
        ),
      ),
      _heading('Seats', tooltip: 'About the ranges and odds', section: '5.'),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Semantics(
          label:
              'Seats out of ${s.seatsTotal}${s.majority == null ? '' : ', majority line ${s.majorityLine}'}',
          child: SizedBox(
            height: 32,
            width: double.infinity,
            child: CustomPaint(
              key: const ValueKey('seats-bar'),
              painter: _SeatsPainter(
                s,
                Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ),
      ),
      if (s.majority != null)
        Text(
          'Majority line: ${s.majorityLine}',
          key: const ValueKey('majority-line'),
        ),
      for (final p in parties)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              PartyDot(p.code),
              const SizedBox(width: 8),
              Text(p.code),
              const Spacer(),
              Text('${s.seats[p.code]!.median}'),
              if (s.seats[p.code]!.low != s.seats[p.code]!.high)
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Text(
                    '${s.seats[p.code]!.low}-${s.seats[p.code]!.high}',
                  ),
                ),
            ],
          ),
        ),
      if (s.majority != null && parties.isNotEmpty)
        Text(
          'Majority: ${parties.first.code} ${((s.majority![parties.first.code] ?? 0) * 100).round()}%',
        ),
      if (s.minority != null) Text(_minorityLine(s.minority!)),
      if (comparison != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            '${comparison.name}: ${Party.values.where((p) => comparison.seats.containsKey(p.code)).map((p) => '${p.code} ${comparison.seats[p.code]!.round()}').join(', ')} (${comparison.asOf}) (different model)',
          ),
        ),
      if (note != null)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('Week of ${note.weekOf}')),
                    IconButton(
                      tooltip: 'About the weekly note',
                      icon: const Icon(Icons.info_outline),
                      onPressed: () => _method('7.'),
                    ),
                  ],
                ),
                const Text('Written by fixed rules from the numbers'),
                Text(note.text),
              ],
            ),
          ),
        ),
      _heading(
        'Polling average',
        tooltip: 'About the polling average',
        section: '2.',
      ),
      PollsLineChart(
        dates: history.map((h) => h.date).toList(),
        values: history.map((h) => h.average).toList(),
      ),
      ShareLegend(shares: latest),
      Wrap(
        spacing: 6,
        children: [
          for (final region in [
            'CAN',
            'ATL',
            'QC',
            'ON',
            'PR',
            'AB',
            'BC',
            'TERR',
          ])
            ChoiceChip(
              label: Text(region),
              selected: _region == region,
              onSelected: (_) => setState(() => _region = region),
            ),
        ],
      ),
      if (s.average[_region] == null)
        const Text('No regional average yet.')
      else
        ShareLegend(shares: s.average[_region]!),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final leaders = _leaders;
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (_summaryLoading)
            const Center(child: CircularProgressIndicator())
          else if (_summaryError case WatchHttpException(status: 404))
            const Text('No projection yet.')
          else if (_summaryError != null)
            _failure(_summaryError!, () => unawaited(_reload()))
          else if (_summary != null)
            ..._projection(_summary!),
          _heading('Leaders'),
          if (_leadersLoading)
            const Center(child: CircularProgressIndicator())
          else if (_leadersError != null)
            _failure(_leadersError!, () => unawaited(_reload()))
          else if (leaders != null) ...[
            const Text('Best PM'),
            for (final p
                in (leaders.bestPm.toList()
                      ..sort((a, b) => b.endDate.compareTo(a.endDate)))
                    .take(5))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${p.firm}, ${p.endDate}'),
                subtitle: Text(
                  p.shares.entries
                      .map((e) => '${e.key} ${e.value.toStringAsFixed(1)}%')
                      .join(', '),
                ),
              ),
            const Text('Approval'),
            for (final p
                in (leaders.approval.toList()
                      ..sort((a, b) => b.endDate.compareTo(a.endDate)))
                    .take(5))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${p.firm}, ${p.endDate}'),
                subtitle: Text(
                  'Approve ${p.approve.toStringAsFixed(1)}%, disapprove ${p.disapprove.toStringAsFixed(1)}%',
                ),
              ),
            TextButton(
              onPressed: () =>
                  (widget.openLink ??
                  (uri) => launchUrl(
                    uri,
                    mode: LaunchMode.externalApplication,
                  ))(Uri.parse(leaders.source.url)),
              child: const Text('Source: Wikipedia, CC BY-SA 4.0'),
            ),
          ],
          _heading('Latest polls'),
          if (_listLoading)
            const Center(child: CircularProgressIndicator())
          else ...[
            for (final p in _polls)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${p.firm}, ${p.endDate}'),
                      Text('Sample: ${p.sample}'),
                      ShareLegend(shares: p.shares),
                    ],
                  ),
                ),
              ),
            if (_listError != null)
              _failure(
                _listError!,
                () => unawaited(
                  _loadList(_generation, before: _polls.isEmpty ? null : _next),
                ),
              ),
            if (_next != null)
              TextButton(
                onPressed: _moreLoading
                    ? null
                    : () {
                        setState(() => _moreLoading = true);
                        unawaited(_loadList(_generation, before: _next));
                      },
                child: Text(_moreLoading ? 'Loading…' : 'More'),
              ),
          ],
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => RidingsScreen(polls: widget.polls),
              ),
            ),
            child: const Text('Ridings'),
          ),
        ],
      ),
    );
  }
}

class _SeatsPainter extends CustomPainter {
  const _SeatsPainter(this.summary, this.tickColor);
  final PollsSummary summary;
  final Color tickColor;
  @override
  void paint(Canvas canvas, Size size) {
    var x = 0.0;
    for (final party in Party.values) {
      final width =
          size.width *
          (summary.seats[party.code]?.median ?? 0) /
          summary.seatsTotal;
      canvas.drawRect(
        Rect.fromLTWH(x, 4, width, size.height - 8),
        Paint()..color = party.color,
      );
      x += width;
    }
    if (summary.majority != null) {
      final tick = size.width * summary.majorityLine / summary.seatsTotal;
      canvas.drawLine(
        Offset(tick, 0),
        Offset(tick, size.height),
        Paint()
          ..color = tickColor
          ..strokeWidth = 3,
      );
    }
  }

  @override
  bool shouldRepaint(_SeatsPainter oldDelegate) =>
      oldDelegate.summary != summary || oldDelegate.tickColor != tickColor;
}

/// Parties that round to under 1% are left out; with none left, says so.
String _minorityLine(Map<String, double> minority) {
  final shown = [
    for (final p in Party.values)
      if (((minority[p.code] ?? 0) * 100).round() >= 1)
        '${p.code} ${(minority[p.code]! * 100).round()}%',
  ];
  return 'Minority: ${shown.isEmpty ? 'under 1% for every party' : shown.join(', ')}';
}
