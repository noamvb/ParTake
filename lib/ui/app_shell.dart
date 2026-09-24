import 'package:flutter/material.dart';

import '../core/library.dart';
import 'browse_screen.dart';
import 'following_screen.dart';
import 'home_screen.dart';
import 'open_request.dart';

/// The navigation frame: Home, Browse and Following, switched by a bottom
/// bar on narrow screens or a side rail on wide ones.
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.source,
    required this.library,
    required this.onOpen,
    this.now,
  });

  final EventSource source;
  final Library library;
  final OpenEvent onOpen;

  /// Defaults to [DateTime.now] when null.
  final DateTime Function()? now;

  static const _wideBreakpoint = 720.0;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const _labels = ['Home', 'Browse', 'Following'];
  static const _icons = [Icons.home, Icons.calendar_month, Icons.star];

  DateTime Function() get _now => widget.now ?? DateTime.now;

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
        BrowseScreen(
          source: widget.source,
          library: widget.library,
          onOpen: widget.onOpen,
          now: _now,
        ),
        FollowingScreen(library: widget.library),
      ],
    );

    final body = wide
        ? Row(
            children: [
              NavigationRail(
                selectedIndex: _index,
                labelType: NavigationRailLabelType.all,
                onDestinationSelected: (i) => setState(() => _index = i),
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('ParTake'),
        actions: [
          IconButton(
            tooltip: 'About',
            icon: const Icon(Icons.info_outline),
            onPressed: _showAbout,
          ),
        ],
      ),
      body: body,
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: [
                for (var i = 0; i < _labels.length; i++)
                  NavigationDestination(
                    icon: Icon(_icons[i]),
                    label: _labels[i],
                  ),
              ],
            ),
    );
  }
}
