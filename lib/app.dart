import 'package:flutter/material.dart';

import 'core/library.dart';
import 'player/player_screen.dart';
import 'ui/app_shell.dart';
import 'ui/open_request.dart';

/// Builds the player for a request; tests replace it to avoid media_kit.
typedef PlayerBuilder = Widget Function(OpenRequest request);

class PartakeApp extends StatefulWidget {
  const PartakeApp({
    super.key,
    required this.source,
    required this.library,
    this.playerBuilder,
    this.now,
    this.openRequests,
  });

  final EventSource source;
  final Library library;
  final PlayerBuilder? playerBuilder;
  final DateTime Function()? now;

  /// Requests to open from outside the UI (tapped alert notifications).
  final Stream<OpenRequest>? openRequests;

  @override
  State<PartakeApp> createState() => _PartakeAppState();
}

class _PartakeAppState extends State<PartakeApp> {
  final _navigator = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    widget.openRequests?.listen(_open);
  }

  void _open(OpenRequest request) {
    _navigator.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) =>
            widget.playerBuilder?.call(request) ??
            PlayerScreen(
              request: request,
              source: widget.source,
              library: widget.library,
            ),
      ),
    );
  }

  ThemeData _theme(Brightness brightness) => ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF2E6B5E),
      brightness: brightness,
    ),
  );

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'ParTake',
    navigatorKey: _navigator,
    theme: _theme(Brightness.light),
    darkTheme: _theme(Brightness.dark),
    home: AppShell(
      source: widget.source,
      library: widget.library,
      onOpen: _open,
      now: widget.now,
    ),
  );
}
