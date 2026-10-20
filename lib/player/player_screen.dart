import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:parlvu/parlvu.dart';

import '../core/library.dart';
import '../platform/background_audio.dart';
import '../platform/pip.dart';
import '../platform/live_captions.dart';
import '../ui/open_request.dart';
import 'media_engine.dart';
import 'player_controller.dart';
import 'player_session.dart';

export 'player_session.dart' show PlayerVideoBuilder, defaultLiveCaptionFeed;

/// The hinge of a half-open device held like a laptop, or null.
Rect? tabletopHinge(MediaQueryData media) {
  for (final feature in media.displayFeatures) {
    final bounds = feature.bounds;
    if (feature.type != DisplayFeatureType.cutout &&
        feature.state == DisplayFeatureState.postureHalfOpened &&
        bounds.width > bounds.height &&
        bounds.top > 0) {
      return bounds;
    }
  }
  return null;
}

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.request,
    required this.source,
    required this.library,
    this.engineFactory,
    this.videoBuilder,
    this.audioHandler,
    this.pip,
    this.liveCaptionsFactory,
    this.session,
  });
  final PlayerSession? session;
  final OpenRequest request;
  final EventSource source;
  final Library library;
  final MediaEngine Function()? engineFactory;
  final PlayerVideoBuilder? videoBuilder;
  final PartakeAudioHandler? audioHandler;
  final PipControl? pip;
  final LiveCaptionFeed Function()? liveCaptionsFactory;
  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with SingleTickerProviderStateMixin {
  late final PlayerSession session;
  PlayerController get controller => session.controller;
  final search = TextEditingController();
  late final TabController _tabs;
  static const rates = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    session =
        widget.session ??
        PlayerSession(
          request: widget.request,
          source: widget.source,
          library: widget.library,
          engineFactory: widget.engineFactory,
          liveCaptionsFactory: widget.liveCaptionsFactory,
          videoBuilder: widget.videoBuilder,
          audioHandler: widget.audioHandler,
          pip: widget.pip,
        );
    session.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    session.removeListener(_changed);
    if (widget.session == null) unawaited(session.close());
    _tabs.dispose();
    search.dispose();
    super.dispose();
  }

  bool get _canSwitchAudio {
    final streams = controller.detail?.streams.where(
      (s) => s.language == controller.language,
    );
    return streams != null &&
        streams.any((s) => s.audioOnly) &&
        streams.any((s) => !s.audioOnly);
  }

  Widget _controls({bool large = false}) {
    if (!large) {
      return _controlWrap([..._transportButtons(), ..._secondaryControls()]);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _transportButtons(large: true),
        ),
        _controlWrap(_secondaryControls()),
      ],
    );
  }

  Widget _controlWrap(List<Widget> children) => Wrap(
    alignment: WrapAlignment.center,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: children,
  );

  List<Widget> _transportButtons({bool large = false}) => [
    _button(
      'Back 30 seconds',
      Icons.replay_30,
      () => controller.seekRelative(const Duration(seconds: -30)),
      iconSize: large ? 36 : null,
    ),
    _button(
      'Back 10 seconds',
      Icons.replay_10,
      () => controller.seekRelative(const Duration(seconds: -10)),
      iconSize: large ? 36 : null,
    ),
    _button(
      controller.playing ? 'Pause' : 'Play',
      controller.playing ? Icons.pause : Icons.play_arrow,
      controller.togglePlay,
      iconSize: large ? 48 : null,
      filled: large,
    ),
    _button(
      'Forward 10 seconds',
      Icons.forward_10,
      () => controller.seekRelative(const Duration(seconds: 10)),
      iconSize: large ? 36 : null,
    ),
    _button(
      'Forward 30 seconds',
      Icons.forward_30,
      () => controller.seekRelative(const Duration(seconds: 30)),
      iconSize: large ? 36 : null,
    ),
  ];

  List<Widget> _secondaryControls() => [
    PopupMenuButton<AudioLanguage>(
      tooltip: 'Audio language',
      onSelected: controller.setLanguage,
      itemBuilder: (_) => AudioLanguage.values
          .where(controller.availableLanguages.contains)
          .map((l) => PopupMenuItem(value: l, child: Text(_langName(l))))
          .toList(),
      child: const Padding(
        padding: EdgeInsets.all(12),
        child: Icon(Icons.language),
      ),
    ),
    IconButton(
      tooltip: controller.captionsOn ? 'Captions on' : 'Captions off',
      onPressed: () => controller.setCaptions(!controller.captionsOn),
      icon: Icon(
        controller.captionsOn ? Icons.closed_caption : Icons.closed_caption_off,
      ),
    ),
    if (_canSwitchAudio)
      _button(
        controller.audioOnly ? 'Show video' : 'Background audio',
        controller.audioOnly ? Icons.videocam : Icons.headphones,
        () => controller.setAudioOnly(!controller.audioOnly),
      ),
    if (session.pip?.available == true)
      _button(
        'Picture in picture',
        Icons.picture_in_picture_alt,
        session.pip!.enter,
      ),
    PopupMenuButton<double>(
      tooltip: 'Speed',
      onSelected: controller.setRate,
      itemBuilder: (_) => rates
          .map((r) => PopupMenuItem(value: r, child: Text('${r}x')))
          .toList(),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text('${controller.rate}x'),
      ),
    ),
    if (controller.isLive) ...[
      const Chip(label: Text('LIVE')),
      // Always laid out so the centred row does not shift when it appears.
      Visibility(
        visible: controller.behindLive,
        maintainSize: true,
        maintainAnimation: true,
        maintainState: true,
        child: TextButton(
          onPressed: controller.goLive,
          child: const Text('Go live'),
        ),
      ),
    ],
  ];

  Widget _button(
    String tip,
    IconData icon,
    Future<void> Function() action, {
    double? iconSize,
    bool filled = false,
  }) {
    if (filled) {
      return IconButton.filled(
        tooltip: tip,
        onPressed: () => unawaited(action()),
        iconSize: iconSize,
        icon: Icon(icon),
      );
    }
    return IconButton(
      tooltip: tip,
      onPressed: () => unawaited(action()),
      iconSize: iconSize,
      icon: Icon(icon),
    );
  }

  static String _langName(AudioLanguage l) => switch (l) {
    AudioLanguage.floor => 'Floor',
    AudioLanguage.english => 'English',
    AudioLanguage.french => 'French',
  };
  Widget _panel({double width = 360}) => SizedBox(
    width: width,
    child: Column(
      children: [
        TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Speakers'),
            Tab(text: 'Search'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [_speakerPanel(), _searchPanel()],
          ),
        ),
      ],
    ),
  );
  Widget _speakerPanel() {
    if (controller.speakersLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.speakers.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            'Speaker list appears once Hansard is published, usually the next day.',
          ),
        ),
      );
    }
    return ListView(
      children: [
        for (final mark in controller.speakers)
          ListTile(
            selected: mark == controller.currentSpeaker,
            title: Text(mark.speech.speaker.split(' (').first),
            trailing: Text(
              '${mark.source == MarkSource.interpolated ? '~' : ''}${_time(_offset(mark))}',
            ),
            onTap: () => unawaited(controller.seekToMark(mark)),
          ),
      ],
    );
  }

  Duration _offset(SpeakerMark m) =>
      controller.detail!.offsetOf(m.wallClock, controller.stream!);
  Widget _searchPanel() {
    final hits = controller.search(search.text);
    if (controller.detail == null ||
        controller.detail!.captions.values.every(
          (captions) => captions.isEmpty,
        )) {
      if (controller.isLive) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Caption search is available once the sitting is archived.',
              ),
              if (controller.language == AudioLanguage.floor &&
                  controller.captionsOn)
                const Text('Live captions come with English or French audio.'),
            ],
          ),
        );
      }
      return const Center(child: Text('No captions for this event.'));
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextField(
            controller: search,
            decoration: const InputDecoration(hintText: 'Search captions'),
            onChanged: (_) => setState(() {}),
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              for (final hit in hits)
                ListTile(
                  title: Text(
                    '${_time(controller.detail!.offsetOf(hit.caption.begin, controller.stream!))}  ${hit.caption.text}',
                  ),
                  onTap: () => unawaited(controller.seekToCaption(hit.caption)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  static String _time(Duration d) {
    final s = d.inSeconds;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${s ~/ 3600}:${two((s ~/ 60) % 60)}:${two(s % 60)}';
  }

  String _errorText() {
    final error = controller.error;
    if (error is! EventNotStartedException) return '$error';
    final start = widget.request.event?.scheduledStart.toLocal();
    if (start == null) return 'This hasn\'t started yet.';
    String two(int n) => n.toString().padLeft(2, '0');
    return 'This hasn\'t started yet. '
        'Scheduled for ${two(start.hour)}:${two(start.minute)}.';
  }

  Widget _holdPill({required Key key, required List<Widget> children}) =>
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: DecoratedBox(
          key: key,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: children),
          ),
        ),
      );

  Widget _videoArea() => GestureDetector(
    onLongPressStart: (_) => unawaited(controller.startHoldFast()),
    onLongPressEnd: (_) => unawaited(controller.endHoldFast()),
    onLongPressCancel: () => unawaited(controller.endHoldFast()),
    child: Stack(
      alignment: Alignment.topCenter,
      children: [
        session.video(),
        if (controller.holdingFast)
          _holdPill(
            key: const ValueKey('hold-fast-pill'),
            children: const [
              Text('2x', style: TextStyle(color: Colors.white, fontSize: 14)),
              SizedBox(width: 4),
              Icon(Icons.fast_forward, color: Colors.white, size: 18),
            ],
          ),
        if (controller.holdBlockedAtLive)
          _holdPill(
            key: const ValueKey('hold-live-pill'),
            children: const [
              Icon(Icons.live_tv, color: Colors.white, size: 18),
              SizedBox(width: 4),
              Text(
                'At live – nothing to speed up',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
            ],
          ),
      ],
    ),
  );

  Widget _body() {
    if (session.pipActive) {
      return SizedBox.expand(child: Center(child: session.video()));
    }
    if (controller.phase == PlayerPhase.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.phase == PlayerPhase.error) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_errorText(), textAlign: TextAlign.center),
            ),
            ElevatedButton(
              onPressed: () => unawaited(controller.open(widget.request)),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    final video = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _videoArea(),
        _controls(),
        if (controller.error != null)
          MaterialBanner(
            content: Text('${controller.error}'),
            actions: [
              TextButton(
                onPressed: controller.dismissError,
                child: const Text('Dismiss'),
              ),
            ],
          ),
      ],
    );
    return LayoutBuilder(
      builder: (context, box) => box.maxWidth >= 900
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: video),
                _panel(),
              ],
            )
          : Column(
              children: [
                video,
                Expanded(child: _panel()),
              ],
            ),
    );
  }

  Widget _minimizeButton() => IconButton(
    tooltip: 'Minimize',
    icon: const Icon(Icons.keyboard_arrow_down),
    onPressed: () {
      session.minimize();
      Navigator.of(context).pop();
    },
  );

  Widget _closeButton() => IconButton(
    tooltip: 'Close player',
    icon: const Icon(Icons.close),
    onPressed: () {
      unawaited(session.close());
      Navigator.of(context).pop();
    },
  );

  Widget _tabletopBody(Rect hinge) => Column(
    children: [
      SizedBox(
        height: hinge.top,
        child: ColoredBox(
          color: Colors.black,
          child: SafeArea(bottom: false, child: Center(child: _videoArea())),
        ),
      ),
      SizedBox(height: hinge.height),
      Expanded(
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Row(
                children: [
                  if (widget.session != null) _minimizeButton(),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: widget.session == null ? 16 : 0,
                      ),
                      child: Text(
                        controller.event?.title ?? widget.request.title,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ),
                  if (widget.session != null) _closeButton(),
                ],
              ),
              _controls(large: true),
              if (controller.error != null)
                MaterialBanner(
                  content: Text('${controller.error}'),
                  actions: [
                    TextButton(
                      onPressed: controller.dismissError,
                      child: const Text('Dismiss'),
                    ),
                  ],
                ),
              Expanded(child: _panel(width: double.infinity)),
            ],
          ),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    // Pop animations retain the route. Unmount its video immediately when
    // minimized so the web's single video element never has two owners.
    if (session.closed || session.minimized) {
      return const SizedBox();
    }
    if (session.pipActive) {
      return SizedBox.expand(child: Center(child: session.video()));
    }
    final hinge = tabletopHinge(MediaQuery.of(context));
    final tabletop =
        hinge != null &&
        controller.phase != PlayerPhase.loading &&
        controller.phase != PlayerPhase.error &&
        !session.pipActive;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && widget.session != null) session.minimize();
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyC): () =>
              controller.setCaptions(!controller.captionsOn),
          const SingleActivator(LogicalKeyboardKey.keyJ): () =>
              unawaited(controller.seekRelative(const Duration(seconds: -30))),
          const SingleActivator(LogicalKeyboardKey.keyL): () =>
              unawaited(controller.seekRelative(const Duration(seconds: 30))),
          const SingleActivator(LogicalKeyboardKey.keyK): () =>
              unawaited(controller.togglePlay()),
          const SingleActivator(LogicalKeyboardKey.bracketLeft): () =>
              _stepRate(-1),
          const SingleActivator(LogicalKeyboardKey.bracketRight): () =>
              _stepRate(1),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            appBar: tabletop
                ? null
                : AppBar(
                    toolbarHeight: 44,
                    leading: widget.session == null ? null : _minimizeButton(),
                    actions: [if (widget.session != null) _closeButton()],
                    title: Text(
                      controller.event?.title ?? widget.request.title,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
            body: tabletop ? _tabletopBody(hinge) : _body(),
          ),
        ),
      ),
    );
  }

  void _stepRate(int delta) {
    final i = rates.indexOf(controller.rate);
    final n = (i + delta).clamp(0, rates.length - 1);
    unawaited(controller.setRate(rates[n]));
  }
}
