import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/library.dart';
import '../platform/app_features.dart';
import '../update/update_check.dart';
import '../polls/polls_client.dart';
import '../watch/watch_follows.dart';
import 'browse_screen.dart';
import 'following_screen.dart';
import 'home_screen.dart';
import 'open_request.dart';
import 'polls_screen.dart';
import 'watch_screen.dart';

enum _Tab { home, watch, polls, browse, following }

/// The navigation frame: Home, Watch, Polls, Browse and Following, switched by a
/// bottom bar on narrow screens or a side rail on wide ones.
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.source,
    required this.library,
    this.watch,
    this.features = const AppFeatures(),
    this.checkForUpdate,
    this.openUrl,
    this.polls,
    required this.onOpen,
    this.now,
    this.overlay,
    this.fullscreenOverlay = false,
  });

  final EventSource source;
  final Library library;
  final WatchFollows? watch;
  final AppFeatures features;
  final Future<UpdateInfo?> Function()? checkForUpdate;
  final void Function(Uri url)? openUrl;
  final PollsClient? polls;
  final OpenEvent onOpen;
  final Widget? overlay;
  final bool fullscreenOverlay;

  /// Defaults to [DateTime.now] when null.
  final DateTime Function()? now;

  static const _wideBreakpoint = 720.0;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  UpdateInfo? _update;

  List<_Tab> get _tabs => [
    _Tab.home,
    if (widget.features.deck) ...[_Tab.watch, _Tab.polls],
    _Tab.browse,
    if (widget.features.following) _Tab.following,
  ];

  /// The Watch tab is built on first visit so its feed is not fetched earlier.
  bool _watchOpened = false;
  bool _pollsOpened = false;
  PollsClient? _ownedPolls;

  static const _labels = ['Home', 'Watch', 'Polls', 'Browse', 'Following'];
  static const _icons = [
    Icons.home,
    Icons.newspaper,
    Icons.bar_chart,
    Icons.calendar_month,
    Icons.star,
  ];

  DateTime Function() get _now => widget.now ?? DateTime.now;

  void _select(int i) => setState(() {
    _index = i;
    if (_tabs[i] == _Tab.watch) _watchOpened = true;
    if (_tabs[i] == _Tab.polls) {
      _pollsOpened = true;
      _pollsClient();
    }
  });

  @override
  void initState() {
    super.initState();
    widget.watch?.addListener(_watchChanged);
    widget.checkForUpdate?.call().then((info) {
      if (mounted && info != null) setState(() => _update = info);
    });
  }

  @override
  void didUpdateWidget(AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldTab = [
      _Tab.home,
      if (oldWidget.features.deck) ...[_Tab.watch, _Tab.polls],
      _Tab.browse,
      if (oldWidget.features.following) _Tab.following,
    ][_index];
    final newIndex = _tabs.indexOf(oldTab);
    _index = newIndex < 0 ? 0 : newIndex;
    if (oldWidget.watch != widget.watch) {
      oldWidget.watch?.removeListener(_watchChanged);
      widget.watch?.addListener(_watchChanged);
    }
  }

  void _watchChanged() => setState(() {});

  PollsClient? _pollsClient() {
    if (widget.polls != null) return widget.polls;
    final address = widget.watch?.address ?? '';
    if (_ownedPolls != null && _ownedPolls!.address.toString() != address) {
      _ownedPolls!.close();
      _ownedPolls = null;
    }
    if (_ownedPolls == null && address.isNotEmpty) {
      _ownedPolls = PollsClient(address: Uri.parse(address));
    }
    return _ownedPolls;
  }

  @override
  void dispose() {
    widget.watch?.removeListener(_watchChanged);
    _ownedPolls?.close();
    super.dispose();
  }

  Widget _pollsTab() {
    if (!_pollsOpened) return const SizedBox.shrink();
    final client = _pollsClient();
    if (client == null ||
        (widget.polls == null && (widget.watch?.address ?? '').isEmpty)) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Set the Deck address in the Watch tab first.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return PollsScreen(key: ValueKey(client), polls: client);
  }

  void _showDigests() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DigestsScreen(
          watch: widget.watch,
          onOpen: widget.onOpen,
          now: _now,
        ),
      ),
    );
  }

  void _showAbout() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('About'),
        content: const Text(
          'Unofficial viewer for ParlVU. Not affiliated with or endorsed by '
          'the House of Commons. Personal, non-commercial use.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= AppShell._wideBreakpoint;

    final content = IndexedStack(
      index: _index,
      children: [
        for (final tab in _tabs)
          switch (tab) {
            _Tab.home => HomeScreen(
              source: widget.source,
              library: widget.library,
              onOpen: widget.onOpen,
              now: _now,
              showFollow: widget.features.following,
            ),
            _Tab.watch =>
              _watchOpened
                  ? WatchScreen(
                      watch: widget.watch,
                      onOpen: widget.onOpen,
                      now: _now,
                    )
                  : const SizedBox.shrink(),
            _Tab.polls => _pollsTab(),
            _Tab.browse => BrowseScreen(
              source: widget.source,
              library: widget.library,
              onOpen: widget.onOpen,
              now: _now,
              showFollow: widget.features.following,
            ),
            _Tab.following => FollowingScreen(
              library: widget.library,
              watch: widget.watch,
              polls: widget.features.deck ? _pollsClient() : null,
            ),
          },
      ],
    );

    final body = wide
        ? Row(
            children: [
              NavigationRail(
                selectedIndex: _index,
                labelType: NavigationRailLabelType.all,
                onDestinationSelected: _select,
                destinations: [
                  for (final tab in _tabs)
                    NavigationRailDestination(
                      icon: Icon(_icons[tab.index]),
                      label: Text(_labels[tab.index]),
                    ),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: content),
            ],
          )
        : content;

    final scaffold = Scaffold(
      appBar: AppBar(
        title: const Text('ParTake'),
        actions: [
          if (_tabs[_index] == _Tab.watch)
            IconButton(
              tooltip: 'Digests',
              icon: const Icon(Icons.summarize_outlined),
              onPressed: _showDigests,
            ),
          IconButton(
            tooltip: 'About',
            icon: const Icon(Icons.info_outline),
            onPressed: _showAbout,
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Column(
            children: [
              if (_update case final info?)
                MaterialBanner(
                  content: Text('ParTake ${info.version} is available.'),
                  actions: [
                    TextButton(
                      onPressed: () {
                        final open = widget.openUrl;
                        if (open != null) {
                          open(info.url);
                        } else {
                          launchUrl(
                            info.url,
                            mode: LaunchMode.externalApplication,
                          );
                        }
                      },
                      child: const Text('Download'),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _update = null),
                      child: const Text('Later'),
                    ),
                  ],
                ),
              Expanded(child: body),
            ],
          ),
          if (widget.overlay != null && !widget.fullscreenOverlay)
            Positioned(right: 12, bottom: 12, child: widget.overlay!),
        ],
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBarTheme(
              data: NavigationBarThemeData(
                labelTextStyle: WidgetStatePropertyAll(
                  Theme.of(context).textTheme.labelSmall,
                ),
              ),
              child: NavigationBar(
                selectedIndex: _index,
                onDestinationSelected: _select,
                destinations: [
                  for (final tab in _tabs)
                    NavigationDestination(
                      icon: Icon(_icons[tab.index]),
                      label: _labels[tab.index],
                    ),
                ],
              ),
            ),
    );
    // Keep the selected tab and browsing state while Android shrinks the
    // activity into a system PiP window.
    return Stack(
      fit: StackFit.expand,
      children: [
        Offstage(offstage: widget.fullscreenOverlay, child: scaffold),
        if (widget.fullscreenOverlay && widget.overlay != null)
          Positioned.fill(child: widget.overlay!),
      ],
    );
  }
}
