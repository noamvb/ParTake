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

class _FeedCard extends StatelessWidget {
  const _FeedCard({
    required this.item,
    required this.follows,
    required this.now,
    required this.expanded,
    required this.onToggle,
    required this.onWatch,
    required this.onOpen,
  });

  final WatchFeedItem item;
  final List<WatchFollow> follows;
  final DateTime now;
  final bool expanded;
  final VoidCallback onToggle;
  final OpenEvent onWatch;
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

  static String _speakerLine(String name, WatchSpeaker speaker) =>
      speaker.party == null ? name : '$name · ${speaker.party}';

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
    final video = item.video;
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
              if (item.source == 'captions')
                Text(
                  'From live captions',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              if (item.kind == 'speech' && speaker != null)
                Text(
                  speaker.from == 'caption_call'
                      ? _speakerLine('Probably ${speaker.name}', speaker)
                      : _speakerLine(speaker.name, speaker),
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
                  if (video != null)
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                      onPressed: () => onWatch(
                        OpenRequest(
                          eventId: int.parse(video.event),
                          title: item.title,
                          eventDate: parliamentDate(video.at),
                          seekTo: video.at,
                        ),
                      ),
                      icon: const Icon(Icons.play_circle_outline),
                      label: const Text('Watch'),
                    ),
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

String _digestTitle(WatchDigestSummary digest) {
  final morning = digest.kind == 'morning';
  final day = morning ? parliamentDate(digest.createdAt) : digest.date;
  final kind = morning ? 'Morning' : 'Evening';
  return '$kind digest, ${_weekdays[day.weekday - 1]} ${day.day} '
      '${_months[day.month - 1]}';
}

/// The digests the Deck has built, newest first.
class DigestsScreen extends StatefulWidget {
  const DigestsScreen({
    super.key,
    required this.watch,
    required this.onOpen,
    this.now,
    this.openLink,
  });

  /// Null when no Deck is set up.
  final WatchFollows? watch;
  final OpenEvent onOpen;

  /// Defaults to [DateTime.now] when null.
  final DateTime Function()? now;

  /// Defaults to opening the link in the browser.
  final Future<bool> Function(Uri uri)? openLink;

  @override
  State<DigestsScreen> createState() => _DigestsScreenState();
}

class _DigestsScreenState extends State<DigestsScreen> {
  List<WatchDigestSummary>? _digests;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.watch != null) unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _digests = null;
      _error = null;
    });
    try {
      final digests = await widget.watch!.digests();
      if (mounted) setState(() => _digests = digests);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _digests = const [];
        _error = _message(error);
      });
    }
  }

  void _openDigest(WatchDigestSummary digest) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => _DigestScreen(
        watch: widget.watch!,
        id: digest.id,
        title: _digestTitle(digest),
        now: widget.now,
        onOpen: widget.onOpen,
        openLink: widget.openLink,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Digests')),
    body: widget.watch == null ? _noDeck() : _body(),
  );

  Widget _body() {
    final digests = _digests;
    final error = _error;
    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error, textAlign: TextAlign.center),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (digests == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (digests.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(_noDigestsText, textAlign: TextAlign.center),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: digests.length,
      itemBuilder: (context, index) {
        final digest = digests[index];
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6),
          child: ListTile(
            title: Text(_digestTitle(digest)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${digest.items} items'),
                if (digest.replaces != null)
                  const Text('Updated with the official record'),
              ],
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openDigest(digest),
          ),
        );
      },
    );
  }
}

/// One digest: a header per follow, then that follow's items as feed cards.
class _DigestScreen extends StatefulWidget {
  const _DigestScreen({
    required this.watch,
    required this.id,
    required this.title,
    required this.now,
    required this.onOpen,
    required this.openLink,
  });

  final WatchFollows watch;
  final String id;
  final String title;
  final DateTime Function()? now;
  final OpenEvent onOpen;
  final Future<bool> Function(Uri uri)? openLink;

  @override
  State<_DigestScreen> createState() => _DigestScreenState();
}

class _DigestScreenState extends State<_DigestScreen> {
  final _expanded = <String>{};
  WatchDigest? _digest;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _digest = null;
      _error = null;
    });
    try {
      final digest = await widget.watch.digest(widget.id);
      if (mounted) setState(() => _digest = digest);
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    }
  }

  Future<bool> _open(Uri uri) => (widget.openLink ?? _launchExternal)(uri);

  /// Playing a moment leaves the digests behind, so the player is not
  /// opened under them.
  void _watch(OpenRequest request) {
    final onOpen = widget.onOpen;
    Navigator.of(context).popUntil((route) => route.isFirst);
    onOpen(request);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final digest = _digest;
    final error = _error;
    final now = (widget.now ?? DateTime.now)();
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(error, textAlign: TextAlign.center),
                  TextButton(onPressed: _load, child: const Text('Retry')),
                ],
              ),
            )
          : digest == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              children: [
                if (digest.opinion != null)
                  ListTile(
                    leading: const Icon(Icons.bar_chart),
                    title: const Text('Polls'),
                    subtitle: Text(digest.opinion!),
                  ),
                for (final section in digest.sections) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 16, bottom: 4),
                    child: Text(
                      section.label,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  for (final item in section.items)
                    _FeedCard(
                      item: item,
                      follows: widget.watch.follows,
                      now: now,
                      expanded: _expanded.contains(item.id),
                      onToggle: () => setState(() {
                        if (!_expanded.remove(item.id)) _expanded.add(item.id);
                      }),
                      onWatch: _watch,
                      onOpen: (url) => _open(Uri.parse(url)),
                    ),
                ],
              ],
            ),
    );
  }
}
