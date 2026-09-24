import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:parlvu/parlvu.dart';

import '../core/library.dart';
import '../ui/open_request.dart';
import 'media_engine.dart';
import 'player_controller.dart';

typedef PlayerVideoBuilder = Widget Function(MediaEngine engine);

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.request,
    required this.source,
    required this.library,
    this.engineFactory,
    this.videoBuilder,
  });
  final OpenRequest request;
  final EventSource source;
  final Library library;
  final MediaEngine Function()? engineFactory;
  final PlayerVideoBuilder? videoBuilder;
  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with SingleTickerProviderStateMixin {
  late final MediaEngine engine;
  late final PlayerController controller;
  final search = TextEditingController();
  late final TabController _tabs;
  static const rates = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    engine = widget.engineFactory?.call() ?? MediaKitEngine();
    controller = PlayerController(
      source: widget.source,
      library: widget.library,
      engine: engine,
    )..addListener(_changed);
    unawaited(controller.open(widget.request));
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    controller.removeListener(_changed);
    unawaited(controller.close());
    _tabs.dispose();
    search.dispose();
    super.dispose();
  }

  VideoController? _videoController;

  Widget _video() {
    Widget child;
    if (widget.videoBuilder != null) {
      child = widget.videoBuilder!(engine);
    } else if (engine is MediaKitEngine) {
      // One VideoController per engine: the screen rebuilds on every
      // position tick, and a new controller per build recreates the texture.
      _videoController ??= VideoController((engine as MediaKitEngine).player);
      child = Video(
        controller: _videoController!,
        controls: AdaptiveVideoControls,
      );
    } else {
      child = const SizedBox.expand();
    }
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        fit: StackFit.expand,
        children: [
          child,
          if (controller.currentCaption != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                margin: const EdgeInsets.all(20),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                color: Colors.black.withValues(alpha: .7),
                child: Text(
                  controller.currentCaption!.text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _controls() => Wrap(
    alignment: WrapAlignment.center,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      _button(
        'Back 30 seconds',
        Icons.replay_30,
        () => controller.seekRelative(const Duration(seconds: -30)),
      ),
      _button(
        'Back 10 seconds',
        Icons.replay_10,
        () => controller.seekRelative(const Duration(seconds: -10)),
      ),
      _button(
        controller.playing ? 'Pause' : 'Play',
        controller.playing ? Icons.pause : Icons.play_arrow,
        controller.togglePlay,
      ),
      _button(
        'Forward 10 seconds',
        Icons.forward_10,
        () => controller.seekRelative(const Duration(seconds: 10)),
      ),
      _button(
        'Forward 30 seconds',
        Icons.forward_30,
        () => controller.seekRelative(const Duration(seconds: 30)),
      ),
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
          controller.captionsOn
              ? Icons.closed_caption
              : Icons.closed_caption_off,
        ),
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
        if (controller.behindLive)
          TextButton(
            onPressed: controller.goLive,
            child: const Text('Go live'),
          ),
      ],
    ],
  );
  Widget _button(String tip, IconData icon, Future<void> Function() action) =>
      IconButton(
        tooltip: tip,
        onPressed: () => unawaited(action()),
        icon: Icon(icon),
      );
  static String _langName(AudioLanguage l) => switch (l) {
    AudioLanguage.floor => 'Floor',
    AudioLanguage.english => 'English',
    AudioLanguage.french => 'French',
  };
  Widget _panel() => SizedBox(
    width: 360,
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

  Widget _body() {
    if (controller.phase == PlayerPhase.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.phase == PlayerPhase.error) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${controller.error}'),
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
        _video(),
        _controls(),
        if (controller.error != null)
          MaterialBanner(
            content: Text('${controller.error}'),
            actions: [
              TextButton(onPressed: () {}, child: const Text('Dismiss')),
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

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
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
        appBar: AppBar(
          toolbarHeight: 44,
          title: Text(
            controller.event?.title ?? widget.request.title,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        body: _body(),
      ),
    ),
  );
  void _stepRate(int delta) {
    final i = rates.indexOf(controller.rate);
    final n = (i + delta).clamp(0, rates.length - 1);
    unawaited(controller.setRate(rates[n]));
  }
}
