import 'package:flutter/material.dart';

import '../core/library.dart';
import '../polls/polls_client.dart';
import '../watch/watch_follows.dart';
import 'browse_screen.dart';
import 'following_screen.dart';
import 'home_screen.dart';
import 'open_request.dart';
import 'polls_screen.dart';
import 'watch_screen.dart';

/// The navigation frame: Home, Watch, Polls, Browse and Following, switched by a
/// bottom bar on narrow screens or a side rail on wide ones.
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.source,
    required this.library,
    this.watch,
    this.polls,
    required this.onOpen,
    this.now,
    this.overlay,
    this.fullscreenOverlay = false,
  });

  final EventSource source;
  final Library library;
  final WatchFollows? watch;
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
    if (i == 1) _watchOpened = true;
    if (i == 2) {
      _pollsOpened = true;
      final address = widget.watch?.address ?? '';
      if (widget.polls == null) {
        if (_ownedPolls != null && _ownedPolls!.address.toString() != address) {
          _ownedPolls!.close();
          _ownedPolls = null;
        }
        if (_ownedPolls == null && address.isNotEmpty) {
          _ownedPolls = PollsClient(address: Uri.parse(address));
        }
      }
    }
  });

  @override
  void dispose() {
    _ownedPolls?.close();
    super.dispose();
  }

  Widget _pollsTab() {
    if (!_pollsOpened) return const SizedBox.shrink();
    final client = widget.polls ?? _ownedPolls;
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
        HomeScreen(
          source: widget.source,
          library: widget.library,
          onOpen: widget.onOpen,
          now: _now,
        ),
        _watchOpened
            ? WatchScreen(watch: widget.watch, onOpen: widget.onOpen, now: _now)
            : const SizedBox.shrink(),
        _pollsTab(),
        BrowseScreen(
          source: widget.source,
          library: widget.library,
          onOpen: widget.onOpen,
          now: _now,
        ),
        FollowingScreen(library: widget.library, watch: widget.watch),
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
                  for (var i = 0; i < _labels.length; i++)
                    NavigationRailDestination(
                      icon: Icon(_icons[i]),
                      label: Text(_labels[i]),
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
          if (_index == 1)
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
          body,
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
                  for (var i = 0; i < _labels.length; i++)
                    NavigationDestination(
                      icon: Icon(_icons[i]),
                      label: _labels[i],
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
