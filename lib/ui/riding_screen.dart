import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../polls/polls_client.dart';
import '../polls/polls_models.dart';
import '../watch/watch_client.dart';

String pollsError(Object error) => switch (error) {
  WatchHttpException(status: 0) => 'Deck unreachable',
  WatchHttpException(:final message) => message,
  _ => 'Deck response invalid',
};

class PartyDot extends StatelessWidget {
  const PartyDot(this.party, {super.key});
  final String party;
  @override
  Widget build(BuildContext context) => Container(
    width: 10,
    height: 10,
    decoration: BoxDecoration(
      color: Party.fromCode(party).color,
      shape: BoxShape.circle,
    ),
  );
}

class ShareLegend extends StatelessWidget {
  const ShareLegend({super.key, required this.shares});
  final Map<String, double> shares;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 12,
    runSpacing: 4,
    children: [
      for (final p in Party.values)
        if (shares.containsKey(p.code))
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PartyDot(p.code),
              const SizedBox(width: 4),
              Text('${p.code} ${shares[p.code]!.toStringAsFixed(1)}%'),
            ],
          ),
    ],
  );
}

class RidingStatusChip extends StatelessWidget {
  const RidingStatusChip(this.status, {super.key});
  final String status;
  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'safe' => ('Safe', Colors.green.shade100),
      'likely' => ('Likely', Colors.lightGreen.shade100),
      'at_risk' => ('At risk', Colors.amber.shade100),
      'projected_loss' => ('Projected loss', Colors.red.shade100),
      _ => (status, Theme.of(context).colorScheme.surfaceContainerHighest),
    };
    return Chip(
      label: Text(label, style: const TextStyle(color: Colors.black87)),
      backgroundColor: color,
    );
  }
}

String _searchKey(String text) {
  var result = text.toLowerCase();
  const groups = {
    'àáâãäå': 'a',
    'ç': 'c',
    'èéêë': 'e',
    'ìíîï': 'i',
    'ñ': 'n',
    'òóôõö': 'o',
    'ùúûü': 'u',
    'ýÿ': 'y',
    'œ': 'oe',
    'æ': 'ae',
  };
  for (final entry in groups.entries) {
    for (final rune in entry.key.runes) {
      result = result.replaceAll(String.fromCharCode(rune), entry.value);
    }
  }
  return result.replaceAll(RegExp('[\u0300-\u036f]'), '');
}

class RidingsScreen extends StatefulWidget {
  const RidingsScreen({super.key, required this.polls});
  final PollsClient polls;
  @override
  State<RidingsScreen> createState() => _RidingsScreenState();
}

class _RidingsScreenState extends State<RidingsScreen> {
  List<RidingSummary>? _ridings;
  Object? _error;
  String _query = '';
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _ridings = null;
    });
    try {
      final data = await widget.polls.ridings();
      if (mounted) setState(() => _ridings = data);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Ridings')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: const InputDecoration(
              labelText: 'Search ridings',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (value) => setState(() => _query = _searchKey(value)),
          ),
        ),
        Expanded(
          child: _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(pollsError(_error!)),
                      TextButton(onPressed: _load, child: const Text('Retry')),
                    ],
                  ),
                )
              : _ridings == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      for (final r in _ridings!.where(
                        (r) => _searchKey(r.name).contains(_query),
                      ))
                        ListTile(
                          title: Text('${r.name} (${r.province})'),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (r.mp == null)
                                const Text('Vacant')
                              else
                                Wrap(
                                  spacing: 6,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    PartyDot(r.mp!.party),
                                    Text('${r.mp!.name} (${r.mp!.party})'),
                                  ],
                                ),
                              Text(
                                'Projected: ${r.projected ?? 'Unavailable'}${r.winProb == null ? '' : ' · ${(r.winProb! * 100).round()}%'}',
                              ),
                              RidingStatusChip(r.status),
                            ],
                          ),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  RidingScreen(polls: widget.polls, id: r.id),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      ],
    ),
  );
}

class RidingScreen extends StatefulWidget {
  const RidingScreen({super.key, required this.polls, required this.id});
  final PollsClient polls;
  final String id;
  @override
  State<RidingScreen> createState() => _RidingScreenState();
}

class _RidingScreenState extends State<RidingScreen> {
  RidingDetail? _riding;
  Object? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _riding = null;
    });
    try {
      final data = await widget.polls.riding(widget.id);
      if (mounted) setState(() => _riding = data);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Widget _bar(String label, double value, Party party) => Padding(
    key: ValueKey('${party.code}-$label'),
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        SizedBox(width: 40, child: Text(label)),
        Expanded(
          child: Semantics(
            label: '${party.code} $label ${value.toStringAsFixed(1)}%',
            child: SizedBox(
              height: 14,
              child: CustomPaint(painter: _ShareBarPainter(value, party.color)),
            ),
          ),
        ),
        SizedBox(
          width: 56,
          child: Text('${value.toStringAsFixed(1)}%', textAlign: TextAlign.end),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final r = _riding;
    final history = r?.history.toList()
      ?..sort((a, b) => a.date.compareTo(b.date));
    return Scaffold(
      appBar: AppBar(title: Text(r?.name ?? 'Riding')),
      body: _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(pollsError(_error!)),
                  TextButton(onPressed: _load, child: const Text('Retry')),
                ],
              ),
            )
          : r == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  Text(
                    r.mp == null ? 'Vacant' : '${r.mp!.name} (${r.mp!.party})',
                  ),
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      RidingStatusChip(r.status),
                      if (r.winProb != null)
                        Text('${(r.winProb! * 100).round()}% win probability'),
                    ],
                  ),
                  Text('Projected winner: ${r.projected ?? 'Unavailable'}'),
                  for (final p in Party.values) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        PartyDot(p.code),
                        const SizedBox(width: 6),
                        Text(p.code),
                      ],
                    ),
                    _bar('2025', r.results2025[p.code] ?? 0, p),
                    _bar('Now', r.projection[p.code] ?? 0, p),
                  ],
                  const SizedBox(height: 16),
                  const Text('Projected shares over time'),
                  PollsLineChart(
                    dates: history!.map((h) => h.date).toList(),
                    values: history.map((h) => h.shares).toList(),
                  ),
                  ShareLegend(shares: r.projection),
                ],
              ),
            ),
    );
  }
}

class _ShareBarPainter extends CustomPainter {
  const _ShareBarPainter(this.share, this.color);
  final double share;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = color.withValues(alpha: 0.15),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width * share.clamp(0, 100) / 100, size.height),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_ShareBarPainter oldDelegate) =>
      oldDelegate.share != share || oldDelegate.color != color;
}

/// Date-scaled share lines; the same chart is used nationally and per riding.
class PollsLineChart extends StatelessWidget {
  PollsLineChart({
    super.key,
    required List<DateTime> dates,
    required List<Map<String, double>> values,
  }) : dates = List.unmodifiable(dates),
       values = List.unmodifiable(values);
  final List<DateTime> dates;
  final List<Map<String, double>> values;
  @override
  Widget build(BuildContext context) {
    if (dates.isEmpty) {
      return const SizedBox(
        height: 80,
        child: Center(child: Text('No history yet.')),
      );
    }
    final maxShare = values.expand((v) => v.values).fold<double>(0, math.max);
    final ceiling = math.max(60.0, maxShare + 5);
    return Column(
      children: [
        Row(
          children: [
            Text('${ceiling.ceil()}%'),
            const Spacer(),
            const Text('Share'),
          ],
        ),
        Semantics(
          label: 'Party share history chart, 0 to ${ceiling.ceil()} percent',
          child: SizedBox(
            height: 160,
            width: double.infinity,
            child: CustomPaint(
              key: const ValueKey('polls-history-chart'),
              painter: _LinePainter(
                dates,
                values,
                ceiling,
                Theme.of(context).colorScheme.outline,
              ),
            ),
          ),
        ),
        Row(
          children: [
            Text(dates.first.toIso8601String().split('T').first),
            const Spacer(),
            Text(dates.last.toIso8601String().split('T').first),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _LinePainter extends CustomPainter {
  const _LinePainter(this.dates, this.values, this.ceiling, this.axisColor);
  final List<DateTime> dates;
  final List<Map<String, double>> values;
  final double ceiling;
  final Color axisColor;
  @override
  void paint(Canvas canvas, Size size) {
    final axis = Paint()
      ..color = axisColor.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), axis);
    }
    final span = dates.last.difference(dates.first).inMilliseconds;
    for (final party in Party.values) {
      final paint = Paint()
        ..color = party.color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      final path = Path();
      var connected = false;
      for (var i = 0; i < dates.length; i++) {
        final value = values[i][party.code];
        if (value == null) {
          connected = false;
          continue;
        }
        final x = span == 0
            ? size.width / 2
            : size.width *
                  dates[i].difference(dates.first).inMilliseconds /
                  span;
        final y = size.height * (1 - value.clamp(0, ceiling) / ceiling);
        if (connected) {
          path.lineTo(x, y);
        } else {
          path.moveTo(x, y);
        }
        connected = true;
        canvas.drawCircle(Offset(x, y), 2, Paint()..color = party.color);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_LinePainter oldDelegate) =>
      oldDelegate.dates != dates ||
      oldDelegate.values != values ||
      oldDelegate.axisColor != axisColor;
}
