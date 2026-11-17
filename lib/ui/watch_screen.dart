import 'dart:async';

import 'package:flutter/material.dart';
import 'package:parlvu/parlvu.dart';
import 'package:url_launcher/url_launcher.dart';

import '../watch/watch_client.dart';
import '../watch/watch_digests.dart';
import '../watch/watch_feed.dart';
import '../watch/watch_follows.dart';
import '../watch/watch_models.dart';
import 'open_request.dart';

part 'digests_screen.dart';
part 'watch_feed_card.dart';

const _listKey = ValueKey('watch-feed-list');
const _liveStripKey = ValueKey('watch-live-strip');
const _feedKinds = ['topic', 'bill', 'mp', 'votes'];
const _setupText =
    'Parliament watch runs on the Deck. Set up the Deck connection in '
    'Following.';
const _noDigestsText =
    'No digests yet. The first one arrives the evening after a sitting.';
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

Future<bool> _launchExternal(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

String _message(Object error) => switch (error) {
  WatchUnauthorized() => 'Wrong token',
  WatchHttpException(status: 0) => 'Deck unreachable',
  WatchHttpException(:final message) => message,
  FormatException() => 'Deck response invalid',
  _ => 'Could not load the feed',
};

Widget _noDeck() => const Center(
  child: Padding(
    padding: EdgeInsets.all(16),
    child: Text(_setupText, textAlign: TextAlign.center),
  ),
);

/// Parliament watch: what the Deck matched against the follows, newest first.
class WatchScreen extends StatefulWidget {
  const WatchScreen({
    super.key,
    required this.watch,
    required this.onOpen,
    this.now,
    this.openLink,
    this.liveInterval = const Duration(seconds: 60),
  });

  /// Null when no Deck is set up.
  final WatchFollows? watch;

  /// Opens a video moment or a live event in the player.
  final OpenEvent onOpen;

  /// Defaults to [DateTime.now] when null.
  final DateTime Function()? now;

  /// Defaults to opening the link in the browser.
  final Future<bool> Function(Uri uri)? openLink;

  /// How often the live strip asks again while the tab is shown.
  final Duration liveInterval;

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
  List<WatchLive> _live = const [];
  Timer? _liveTimer;
  bool _shown = false;

  /// Bumped by every reload so answers to an older filter are dropped.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    if (widget.watch != null) unawaited(_reload());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The tab is hidden (TickerMode off) until the user opens it.
    final shown = TickerMode.valuesOf(context).enabled;
    if (shown == _shown) return;
    _shown = shown;
    _liveTimer?.cancel();
    _liveTimer = null;
    if (!shown || widget.watch == null) return;
    unawaited(_refreshLive());
    _liveTimer = Timer.periodic(widget.liveInterval, (_) => _refreshLive());
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _refreshLive() async {
    final watch = widget.watch;
    if (watch == null) return;
    try {
      final rows = await watch.live();
      if (mounted) setState(() => _live = rows);
    } catch (_) {
      // The strip is extra: when the Deck cannot say, it is hidden silently.
      if (mounted) setState(() => _live = const []);
    }
  }

  void _openLive(WatchLive live) => widget.onOpen(
    OpenRequest(
      eventId: int.parse(live.event),
      title: live.title,
      eventDate: parliamentDate((widget.now ?? DateTime.now)()),
    ),
  );

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

  Future<bool> _open(Uri uri) => (widget.openLink ?? _launchExternal)(uri);

  @override
  Widget build(BuildContext context) {
    final watch = widget.watch;
    if (watch == null) return _noDeck();
    return ListenableBuilder(
      listenable: watch,
      builder: (context, _) => Column(
        children: [
          _filters(watch),
          _liveStrip(),
          Expanded(child: _results(watch)),
        ],
      ),
    );
  }

  Widget _liveStrip() {
    if (_live.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Column(
        key: _liveStripKey,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final live in _live)
            Card(
              margin: const EdgeInsets.only(bottom: 6),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _openLive(live),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red.shade700,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'LIVE',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              live.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall,
                            ),
                          ),
                        ],
                      ),
                      if (live.speaker != null)
                        Text(
                          'Now: Probably ${live.speaker!.name}',
                          style: theme.textTheme.bodyMedium,
                        ),
                    ],
                  ),
                ),
              ),
            ),
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
            onWatch: widget.onOpen,
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
