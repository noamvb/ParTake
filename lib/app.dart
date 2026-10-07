import 'dart:async';

import 'package:flutter/material.dart';

import 'core/library.dart';
import 'platform/background_audio.dart';
import 'platform/pip.dart';
import 'player/player_screen.dart';
import 'player/player_session.dart';
import 'player/mini_player.dart';
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
    this.sessionFactory,
    this.now,
    this.openRequests,
    this.audioHandler,
  });

  final EventSource source;
  final Library library;
  final PlayerBuilder? playerBuilder;
  final PlayerSession Function(OpenRequest request)? sessionFactory;
  final DateTime Function()? now;

  /// Requests to open from outside the UI (tapped alert notifications).
  final Stream<OpenRequest>? openRequests;
  final PartakeAudioHandler? audioHandler;

  @override
  State<PartakeApp> createState() => _PartakeAppState();
}

class _PartakeAppState extends State<PartakeApp> {
  final _navigator = GlobalKey<NavigatorState>();
  StreamSubscription<OpenRequest>? _openSubscription;
  PlayerSession? _session;
  MaterialPageRoute<void>? _playerRoute;
  Future<void> _pendingOpen = Future<void>.value();

  @override
  void initState() {
    super.initState();
    _openSubscription = widget.openRequests?.listen(_open);
  }

  void _open(OpenRequest request) {
    final builder = widget.playerBuilder;
    if (builder != null) {
      _navigator.currentState?.push(
        MaterialPageRoute<void>(builder: (_) => builder(request)),
      );
      return;
    }
    // Serialize external requests with UI taps so replacing a loading session
    // finishes its teardown before attaching the next audio handler.
    _pendingOpen = _pendingOpen.then((_) => _openSession(request));
  }

  Future<void> _openSession(OpenRequest request) async {
    if (!mounted) return;
    final leavingRoute = _playerRoute;
    if (leavingRoute != null && !leavingRoute.isActive) {
      // A rapid tap on the mini player can arrive during the pop animation.
      // Wait until that route unmounts before expanding the same session.
      await leavingRoute.completed;
      if (!mounted) return;
    }
    var session = _session;
    if (session == null ||
        session.closed ||
        session.request.eventId != request.eventId) {
      if (session != null) {
        session.removeListener(_sessionChanged);
        _session = null;
        await session.close();
        if (!mounted) return;
      }
      final previousRoute = _playerRoute;
      if (previousRoute != null) {
        _playerRoute = null;
        _navigator.currentState?.removeRoute(previousRoute);
      }
      session =
          widget.sessionFactory?.call(request) ??
          PlayerSession(
            request: request,
            source: widget.source,
            library: widget.library,
            audioHandler: widget.audioHandler,
            pip: createPipControl(),
          );
      _session = session;
      session.addListener(_sessionChanged);
    }
    final current = session;
    current.expand();
    setState(() {});
    if (_playerRoute?.isActive == true) return;
    final route = MaterialPageRoute<void>(
      builder: (_) => PlayerScreen(
        request: current.request,
        source: widget.source,
        library: widget.library,
        session: current,
      ),
    );
    _playerRoute = route;
    unawaited(_navigator.currentState?.push(route));
    unawaited(
      route.completed.then((_) {
        if (identical(_playerRoute, route)) _playerRoute = null;
      }),
    );
  }

  void _sessionChanged() {
    final session = _session;
    if (session?.closed == true) {
      session!.removeListener(_sessionChanged);
      _session = null;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    unawaited(_openSubscription?.cancel());
    final session = _session;
    session?.removeListener(_sessionChanged);
    if (session != null) unawaited(session.close());
    super.dispose();
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
      overlay: _session?.minimized == true
          ? _session!.pipActive
                ? ColoredBox(
                    color: Colors.black,
                    child: Center(child: _session!.video()),
                  )
                : MiniPlayer(
                    session: _session!,
                    onExpand: () => _open(_session!.request),
                  )
          : null,
      fullscreenOverlay: _session?.minimized == true && _session!.pipActive,
    ),
  );
}
