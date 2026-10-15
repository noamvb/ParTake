import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../pm/pm_client.dart';
import '../pm/pm_logic.dart';
import '../pm/pm_models.dart';
import '../watch/watch_client.dart';
import 'pm_map.dart';

class PmScreen extends StatefulWidget {
  const PmScreen({
    super.key,
    required this.pm,
    this.now,
    this.showTiles = true,
  });
  final PmClient pm;
  final DateTime Function()? now;
  final bool showTiles;
  @override
  State<PmScreen> createState() => _PmScreenState();
}

class _PmScreenState extends State<PmScreen> {
  String _view = 'Today';
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'Today', label: Text('Today')),
            ButtonSegment(value: 'Feed', label: Text('Feed')),
            ButtonSegment(value: 'Map', label: Text('Map')),
          ],
          selected: {_view},
          onSelectionChanged: (s) => setState(() => _view = s.single),
        ),
      ),
      Expanded(
        child: switch (_view) {
          'Feed' => _Feed(pm: widget.pm, now: widget.now ?? DateTime.now),
          'Map' => PmMap(
            pm: widget.pm,
            now: widget.now ?? DateTime.now,
            showTiles: widget.showTiles,
          ),
          _ => _Today(pm: widget.pm, now: widget.now ?? DateTime.now),
        },
      ),
    ],
  );
}

Future<bool> _open(String url) =>
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
String _date(DateTime value) => value.toIso8601String().substring(0, 10);

Widget pmFailure(Object error, VoidCallback retry) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text(
      'Could not load PM information. ${error is WatchHttpException ? error.message : error}',
    ),
    TextButton(onPressed: retry, child: const Text('Retry')),
  ],
);

Widget pmEvent(PmEvent event) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 8),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('${event.localTime} · ${event.place.name}'),
      if (ottawaLabel(event) case final label?) Text(label),
      Text(event.text),
      if (event.venue case final venue?) Text(venue),
      if (event.media case final media?)
        Chip(
          label: Text(switch (media) {
            'open' => 'Open to media',
            'closed' => 'Closed',
            'pool' => 'Pool',
            _ => media,
          }),
        ),
    ],
  ),
);

class _Today extends StatefulWidget {
  const _Today({required this.pm, required this.now});
  final PmClient pm;
  final DateTime Function() now;
  @override
  State<_Today> createState() => _TodayState();
}

class _TodayState extends State<_Today> {
  late Future<PmToday> _future;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _future = widget.pm.today();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() => _future = widget.pm.today());
    try {
      await _future;
    } catch (_) {
      /* Shown by FutureBuilder. */
    }
  }

  Widget _card(String title, List<Widget> children) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          ...children,
        ],
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: _reload,
    child: FutureBuilder<PmToday>(
      future: _future,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final now = widget.now().toUtc();
        final date = ottawaDate(now);
        final state = data == null ? null : nowAndNext(data, now);
        final next = state?.next;
        return ListView(
          padding: const EdgeInsets.all(16),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (snapshot.connectionState == ConnectionState.waiting)
              const Center(child: CircularProgressIndicator())
            else if (snapshot.hasError)
              pmFailure(snapshot.error!, _reload)
            else if (data != null) ...[
              _card('Now', [
                if (state?.now.place case final place?) Text(place.name),
                Text(state?.now.event?.text ?? 'No public event right now'),
              ]),
              _card('Next', [
                if (next == null)
                  const Text('No upcoming public event')
                else ...[
                  pmEvent(next),
                  Text(_countdown(next.startsAt!.difference(now))),
                ],
              ]),
              if (data.days.isEmpty)
                const Text(
                  'No itinerary published yet. The PMO posts tomorrow\'s around 5 p.m.',
                ),
              for (final day in data.days) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 20, bottom: 8),
                  child: Text(
                    '${day.date == _date(date)
                        ? 'Today'
                        : day.date == _date(date.add(const Duration(days: 1)))
                        ? 'Tomorrow'
                        : 'Itinerary'} · ${day.date}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                for (final note in day.notes) Text(note),
                for (final event in day.events) pmEvent(event),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => _open(day.url),
                    child: const Text('Itinerary on pm.gc.ca'),
                  ),
                ),
              ],
            ],
          ],
        );
      },
    ),
  );
}

String _countdown(Duration duration) {
  final minutes = duration.inMinutes;
  return minutes >= 60
      ? 'in ${minutes ~/ 60} h ${minutes % 60} min'
      : 'in $minutes min';
}

String _relative(DateTime date, DateTime now) {
  final age = now.difference(date);
  if (age.isNegative) return _date(date);
  if (age.inMinutes < 60) return '${age.inMinutes} min ago';
  if (age.inHours < 24) return '${age.inHours} h ago';
  return '${age.inDays} d ago';
}

class _Feed extends StatefulWidget {
  const _Feed({required this.pm, required this.now});
  final PmClient pm;
  final DateTime Function() now;
  @override
  State<_Feed> createState() => _FeedState();
}

class _FeedState extends State<_Feed> {
  final _scroll = ScrollController();
  final _items = <FeedItem>[];
  String? _type, _next;
  Object? _error;
  bool _loading = true, _more = false;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    unawaited(_reload());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.extentAfter < 160 &&
        !_loading &&
        !_more &&
        _next != null &&
        _error == null) {
      unawaited(_load(_generation, before: _next));
    }
  }

  Future<void> _reload() {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _more = false;
      _error = null;
    });
    return _load(generation);
  }

  Future<void> _load(int generation, {String? before}) async {
    if (before != null) setState(() => _more = true);
    try {
      final page = await widget.pm.feed(type: _type, before: before);
      if (!mounted || generation != _generation) return;
      setState(() {
        if (before == null) _items.clear();
        _items.addAll(page.items);
        _next = page.next;
        _error = null;
      });
    } catch (error) {
      if (mounted && generation == _generation) setState(() => _error = error);
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _more = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Wrap(
          spacing: 6,
          children: [
            for (final entry in const <String, String?>{
              'All': null,
              'Itineraries': 'itinerary',
              'Readouts': 'readout',
              'Releases': 'release',
              'Statements': 'statement',
              'Speeches': 'speech',
            }.entries)
              ChoiceChip(
                label: Text(entry.key),
                selected: _type == entry.value,
                onSelected: (_) {
                  _type = entry.value;
                  unawaited(_reload());
                },
              ),
          ],
        ),
      ),
      Expanded(
        child: RefreshIndicator(
          onRefresh: _reload,
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollUpdateNotification ||
                  notification is OverscrollNotification) {
                _onScroll();
              }
              return false;
            },
            child: ListView(
              key: const ValueKey('pm-feed-list'),
              controller: _scroll,
              padding: const EdgeInsets.all(16),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                if (_loading)
                  const Center(child: CircularProgressIndicator())
                else ...[
                  if (_items.isEmpty && _error == null)
                    const Text('No published items yet.'),
                  for (final item in _items)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(item.title),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${item.type} · ${_relative(item.publishedAt, widget.now())}',
                          ),
                          Text(
                            item.summary,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                      onTap: () {
                        if (widget.pm.isSnapshot) {
                          unawaited(_open(item.url));
                        } else {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  _ItemPage(pm: widget.pm, id: item.id),
                            ),
                          );
                        }
                      },
                    ),
                  if (_error != null)
                    pmFailure(
                      _error!,
                      () => _load(
                        _generation,
                        before: _items.isEmpty ? null : _next,
                      ),
                    ),
                  if (_more) const Center(child: CircularProgressIndicator()),
                ],
              ],
            ),
          ),
        ),
      ),
    ],
  );
}

class _ItemPage extends StatefulWidget {
  const _ItemPage({required this.pm, required this.id});
  final PmClient pm;
  final String id;
  @override
  State<_ItemPage> createState() => _ItemPageState();
}

class _ItemPageState extends State<_ItemPage> {
  late Future<PmItem> _future;
  @override
  void initState() {
    super.initState();
    _future = widget.pm.item(widget.id);
  }

  Future<void> _reload() async {
    setState(() => _future = widget.pm.item(widget.id));
    try {
      await _future;
    } catch (_) {
      /* Shown by FutureBuilder. */
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('PM item')),
    body: RefreshIndicator(
      onRefresh: _reload,
      child: FutureBuilder<PmItem>(
        future: _future,
        builder: (context, snapshot) => ListView(
          padding: const EdgeInsets.all(16),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (snapshot.connectionState == ConnectionState.waiting)
              const Center(child: CircularProgressIndicator())
            else if (snapshot.hasError)
              pmFailure(snapshot.error!, _reload)
            else if (snapshot.data case final item?) ...[
              Text(
                item.title,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text(_date(item.publishedAt)),
              for (final paragraph in item.text.split(RegExp(r'\n\s*\n')))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(paragraph),
                ),
              for (final event in item.events) pmEvent(event),
              TextButton(
                onPressed: () => _open(item.url),
                child: const Text('Open on pm.gc.ca'),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
