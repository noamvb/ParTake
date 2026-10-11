import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../watch/watch_client.dart';
import '../watch/watch_feed.dart';
import '../watch/watch_follows.dart';
import '../watch/watch_models.dart';

const _listKey = ValueKey('watch-feed-list');
const _feedKinds = ['topic', 'bill', 'mp', 'votes'];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
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

/// Parliament watch: what the Deck matched against the follows, newest first.
class WatchScreen extends StatefulWidget {
  const WatchScreen({super.key, required this.watch, this.now, this.openLink});

  /// Null when no Deck is set up.
  final WatchFollows? watch;

  /// Defaults to [DateTime.now] when null.
  final DateTime Function()? now;

  /// Defaults to opening the link in the browser.
  final Future<bool> Function(Uri uri)? openLink;

  @override
  State<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends State<WatchScreen> {
  final _scroll = ScrollController();
  final _expanded = <String>{};
  String? _filter;
  List<WatchFeedItem> _items = const [];
  String? _next;
  bool _loading = false;
  bool _loadingMore = false;
  bool _moreFailed = false;
  String? _error;

  /// Bumped by every reload so answers to an older filter are dropped.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    if (widget.watch != null) unawaited(_reload());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<WatchFeedPage> _fetch({String? before}) =>
      widget.watch!.feed(follows: [?_filter], before: before);

  Future<void> _reload() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _loadingMore = false;
      _moreFailed = false;
      _error = null;
    });
    try {
      final page = await _fetch();
      if (!mounted || generation != _generation) return;
      setState(() {
        _items = page.items;
        _next = page.next;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _items = const [];
        _next = null;
        _error = _message(error);
      });
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadMore() async {
    final before = _next;
    if (before == null || _loading || _loadingMore) return;
    final generation = _generation;
    setState(() {
      _loadingMore = true;
      _moreFailed = false;
    });
    try {
      final page = await _fetch(before: before);
      if (!mounted || generation != _generation) return;
      final seen = {for (final item in _items) item.id};
      setState(() {
        _items = [
          ..._items,
          for (final item in page.items)
            if (seen.add(item.id)) item,
        ];
        _next = page.next;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() => _moreFailed = true);
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loadingMore = false);
      }
    }
  }

  void _onScroll() {
    if (_scroll.hasClients && _scroll.position.extentAfter < 300) {
      unawaited(_loadMore());
    }
  }

  void _select(String? id) {
    if (id == _filter) return;
    setState(() {
      _filter = id;
      _items = const [];
      _next = null;
    });
    unawaited(_reload());
  }

  Future<bool> _open(Uri uri) => widget.openLink != null
      ? widget.openLink!(uri)
      : launchUrl(uri, mode: LaunchMode.externalApplication);

  static String _message(Object error) => switch (error) {
    WatchUnauthorized() => 'Wrong token',
    WatchHttpException(status: 0) => 'Deck unreachable',
    WatchHttpException(:final message) => message,
    FormatException() => 'Deck response invalid',
    _ => 'Could not load the feed',
  };

  @override
  Widget build(BuildContext context) {
    final watch = widget.watch;
    if (watch == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Parliament watch runs on the Deck. Set up the Deck connection in '
            'Following.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListenableBuilder(
      listenable: watch,
      builder: (context, _) => Column(
        children: [
          _filters(watch),
          Expanded(child: _results(watch)),
        ],
      ),
    );
  }

  Widget _filters(WatchFollows watch) {
    final choices = [
      for (final follow in watch.follows)
        if (follow.id != null && _feedKinds.contains(follow.kind)) follow,
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          ChoiceChip(
            label: const Text('All'),
            selected: _filter == null,
            onSelected: (_) => _select(null),
          ),
          for (final follow in choices)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: ChoiceChip(
                label: Text(follow.label),
                selected: _filter == follow.id,
                onSelected: (_) => _select(follow.id),
              ),
            ),
        ],
      ),
    );
  }

  Widget _results(WatchFollows watch) {
    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _reload,
        child: LayoutBuilder(
          builder: (context, constraints) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              SizedBox(
                height: constraints.maxHeight,
                child: Center(child: _emptyState()),
              ),
            ],
          ),
        ),
      );
    }
    final now = (widget.now ?? DateTime.now)();
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.builder(
        key: _listKey,
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        itemCount: _items.length + (_loadingMore || _moreFailed ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _items.length) return _footer();
          final item = _items[index];
          return _FeedCard(
            item: item,
            follows: watch.follows,
            now: now,
            expanded: _expanded.contains(item.id),
            onToggle: () => setState(() {
              if (!_expanded.remove(item.id)) _expanded.add(item.id);
            }),
            onOpen: (url) => _open(Uri.parse(url)),
          );
        },
      ),
    );
  }

  Widget _emptyState() {
    if (_loading) return const CircularProgressIndicator();
    if (_error != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_error!, textAlign: TextAlign.center),
          TextButton(onPressed: _reload, child: const Text('Retry')),
        ],
      );
    }
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Text(
        'Nothing has matched your follows yet.',
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _footer() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Center(
      child: _loadingMore
          ? const CircularProgressIndicator()
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Could not load more.'),
                TextButton(onPressed: _loadMore, child: const Text('Retry')),
              ],
            ),
    ),
  );
}

class _FeedCard extends StatelessWidget {
  const _FeedCard({
    required this.item,
    required this.follows,
    required this.now,
    required this.expanded,
    required this.onToggle,
    required this.onOpen,
  });

  final WatchFeedItem item;
  final List<WatchFollow> follows;
  final DateTime now;
  final bool expanded;
  final VoidCallback onToggle;
  final void Function(String url) onOpen;

  static IconData _icon(String kind) => switch (kind) {
    'speech' => Icons.record_voice_over,
    'division' => Icons.how_to_vote,
    'bill_stage' => Icons.gavel,
    _ => Icons.article,
  };

  static String _when(DateTime at, DateTime now) {
    final local = at.toLocal();
    final clock =
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
    final today = now.toLocal();
    if (local.year == today.year &&
        local.month == today.month &&
        local.day == today.day) {
      return 'Today, $clock';
    }
    return '${_weekdays[local.weekday - 1]} ${local.day} '
        '${_months[local.month - 1]}, $clock';
  }

  static String _result(String result) => switch (result) {
    'agreed' => 'Agreed to',
    'negatived' => 'Negatived',
    'tie' => 'Tie',
    _ => result,
  };

  static String _vote(String vote) => switch (vote) {
    'yea' => 'Yea',
    'nay' => 'Nay',
    'paired' => 'Paired',
    _ => vote,
  };

  String _mpLabel(String personId) {
    for (final follow in follows) {
      if (follow.kind == 'mp' && follow.mp?.personId == personId) {
        return follow.label;
      }
    }
    return personId;
  }

  WatchFollow? _followById(String id) {
    for (final follow in follows) {
      if (follow.id == id) return follow;
    }
    return null;
  }

  List<String> _matchedLabels() {
    final labels = <String>[];
    for (final match in item.follows) {
      final follow = _followById(match.id);
      if (follow == null) continue;
      final percent = follow.kind == 'topic' && match.score < 1;
      labels.add(
        percent
            ? '${follow.label} ${(match.score * 100).round()}%'
            : follow.label,
      );
    }
    return labels;
  }

  List<Widget> _divisionLines(ThemeData theme, WatchDivision division) => [
    Text(
      '${_result(division.result)} · ${division.yeas} yea, '
      '${division.nays} nay, ${division.paired} paired',
      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
    ),
    for (final party in division.parties)
      if (party.split)
        Text(
          '${party.party} split: ${party.yea} yea, ${party.nay} nay',
          style: theme.textTheme.bodySmall,
        ),
    for (final mp in division.mps)
      Text(
        '${_mpLabel(mp.personId)}: ${_vote(mp.vote)}',
        style: theme.textTheme.bodySmall,
      ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final speaker = item.speaker;
    final division = item.division;
    final matched = _matchedLabels();
    final links = item.links;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_icon(item.kind), size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _when(item.at, now),
                      style: theme.textTheme.labelMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                item.title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (item.kind == 'speech' && speaker != null)
                Text(
                  speaker.party == null
                      ? speaker.name
                      : '${speaker.name} · ${speaker.party}',
                  style: theme.textTheme.bodyMedium,
                ),
              const SizedBox(height: 4),
              Text(
                item.text,
                maxLines: expanded ? null : 4,
                overflow: TextOverflow.ellipsis,
              ),
              if (division != null) ..._divisionLines(theme, division),
              if (matched.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final label in matched)
                        Chip(
                          label: Text(label),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ),
              Wrap(
                children: [
                  if (links.hansard != null)
                    TextButton(
                      onPressed: () => onOpen(links.hansard!),
                      child: Text(
                        item.source == 'evidence' ? 'Evidence' : 'Hansard',
                      ),
                    ),
                  if (links.legisinfo != null)
                    TextButton(
                      onPressed: () => onOpen(links.legisinfo!),
                      child: const Text('LEGISinfo'),
                    ),
                  if (links.division != null)
                    TextButton(
                      onPressed: () => onOpen(links.division!),
                      child: const Text('Vote details'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
