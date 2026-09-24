import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:parlvu/parlvu.dart';

import '../core/library.dart';
import '../platform/live_captions.dart';
import '../ui/open_request.dart';
import 'caption_index.dart';
import 'media_engine.dart';

enum PlayerPhase { loading, ready, error }

class PlayerController extends ChangeNotifier {
  PlayerController({
    required this.source,
    required this.library,
    required this.engine,
    LiveCaptionFeed? liveCaptions,
    DateTime Function()? now,
    this.saveEvery = const Duration(seconds: 15),
  }) : now = now ?? DateTime.now {
    if (liveCaptions != null) {
      _subscriptions.add(
        liveCaptions.text.listen((value) {
          if (liveCaptionText == value) return;
          liveCaptionText = value;
          notifyListeners();
        }),
      );
    }
    _subscriptions.addAll([
      engine.positionStream.listen(_positionChanged),
      engine.durationStream.listen((_) {
        _recompute();
        notifyListeners();
      }),
      engine.playingStream.listen((value) {
        if (!value) unawaited(_save());
        _recompute();
      }),
      engine.errorStream.listen((value) {
        error = value;
        notifyListeners();
      }),
    ]);
  }

  final EventSource source;
  final Library library;
  final MediaEngine engine;
  final DateTime Function() now;
  final Duration saveEvery;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  PlayerPhase phase = PlayerPhase.loading;
  Object? error;
  ListingEvent? event;
  EventDetail? detail;
  StreamVariant? stream;
  AudioLanguage language = AudioLanguage.floor;
  bool captionsOn = true;
  List<SpeakerMark> speakers = [];
  List<LanguageSwitch> floorSwitches = [];
  bool speakersLoading = false;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  bool playing = false;
  double rate = 1;
  Caption? currentCaption;
  String? liveCaptionText;
  SpeakerMark? currentSpeaker;
  DateTime? _lastSave;

  Set<AudioLanguage> get availableLanguages =>
      detail?.streams.map((s) => s.language).toSet() ?? {};
  bool get isLive => stream?.isLive ?? false;

  /// Text for the caption overlay.
  String? get captionText =>
      isLive ? (captionsOn ? liveCaptionText : null) : currentCaption?.text;
  bool get behindLive => isLive && duration - position > liveBehindThreshold;
  List<Caption> get _captionList {
    final map = detail?.captions ?? const <AudioLanguage, List<Caption>>{};
    final wall = stream == null || detail == null
        ? null
        : detail!.wallClockAt(position, stream!);
    final wanted =
        language == AudioLanguage.floor &&
            floorSwitches.isNotEmpty &&
            wall != null
        ? floorLanguageAt(floorSwitches, wall) ?? AudioLanguage.english
        : language == AudioLanguage.french
        ? AudioLanguage.french
        : AudioLanguage.english;
    final preferred = map[wanted];
    if (preferred != null && preferred.isNotEmpty) return preferred;
    return map[wanted == AudioLanguage.french
            ? AudioLanguage.english
            : AudioLanguage.french] ??
        const [];
  }

  Future<void> open(OpenRequest request) async {
    _requestDate = request.eventDate;
    phase = PlayerPhase.loading;
    error = null;
    notifyListeners();
    try {
      final loaded = await source.detail(request.eventId);
      detail = loaded;
      language = library.settings.language;
      captionsOn = library.settings.captions;
      stream = loaded.preferredStream(language);
      if (stream == null) throw StateError('No playable stream is available.');
      language = stream!.language;
      await engine.open(
        stream!.url,
        start: stream!.isLive ? null : request.resumeAt,
      );
      await engine.setRate(rate);
      position = engine.position;
      duration = engine.duration;
      playing = engine.playing;
      _lastSave = now();
      phase = PlayerPhase.ready;
      event = request.event;
      if (event == null) {
        final day = await source.day(request.eventDate);
        event = day.where((row) => row.id == request.eventId).firstOrNull;
      }
      _recompute();
      notifyListeners();
      if (event != null) unawaited(_loadSpeakers(event!, loaded));
    } catch (e) {
      phase = PlayerPhase.error;
      error = e;
      notifyListeners();
    }
  }

  Future<void> _loadSpeakers(ListingEvent row, EventDetail loaded) async {
    speakersLoading = true;
    speakers = [];
    floorSwitches = [];
    notifyListeners();
    try {
      speakers = await source.speakers(row, loaded);
      floorSwitches = floorLanguageSwitches(speakers, loaded.captions);
    } catch (_) {
      speakers = [];
      floorSwitches = [];
    }
    speakersLoading = false;
    _recompute();
    notifyListeners();
  }

  Future<void> setLanguage(AudioLanguage value) async {
    if (value == language || detail == null) return;
    final at = position;
    final next = detail!.preferredStream(value);
    if (next == null) return;
    stream = next;
    language = next.language;
    await engine.open(next.url, start: next.isLive && !behindLive ? null : at);
    await engine.setRate(rate);
    _recompute();
    notifyListeners();
  }

  void setCaptions(bool on) {
    if (captionsOn == on) return;
    captionsOn = on;
    _recompute();
    notifyListeners();
  }

  Future<void> togglePlay() async {
    if (playing) {
      await engine.pause();
      playing = false;
    } else {
      await engine.play();
      playing = true;
    }
    notifyListeners();
  }

  Future<void> seek(Duration value) async {
    final clamped = value < Duration.zero
        ? Duration.zero
        : duration > Duration.zero && value > duration
        ? duration
        : value;
    await engine.seek(clamped);
    position = clamped;
    _recompute();
    notifyListeners();
  }

  Future<void> seekRelative(Duration delta) => seek(position + delta);
  Future<void> seekToMark(SpeakerMark mark) =>
      seek(detail!.offsetOf(mark.wallClock, stream!));
  Future<void> seekToCaption(Caption caption) {
    final target =
        detail!.offsetOf(caption.begin, stream!) - const Duration(seconds: 2);
    return seek(target < Duration.zero ? Duration.zero : target);
  }

  /// How far short of the live edge [goLive] lands. ParlVU publishes 10 s
  /// segments (target duration 12 s); landing closer than about three of
  /// them plays into the edge and stalls repeatedly (measured 2026-09-24:
  /// 3.5 s at the edge, 9 s and 12 s stalls from 12 s short). hls.js itself
  /// opens a live stream 40-45 s behind.
  static const liveEdgeMargin = Duration(seconds: 36);

  /// Behind the edge by more than this, the player offers "Go live". Kept
  /// above hls.js's own live position so a freshly opened stream is "live".
  static const liveBehindThreshold = Duration(seconds: 60);

  Future<void> goLive() => seek(
    duration > liveEdgeMargin ? duration - liveEdgeMargin : Duration.zero,
  );
  Future<void> setRate(double value) async {
    const allowed = [0.75, 1, 1.25, 1.5, 1.75, 2];
    if (!allowed.contains(value)) throw ArgumentError.value(value, 'rate');
    rate = value;
    await engine.setRate(value);
    notifyListeners();
  }

  List<CaptionHit> search(String query) {
    final list = language == AudioLanguage.floor
        ? (detail?.captions[AudioLanguage.english] ?? const <Caption>[])
        : _captionList;
    return CaptionIndex(list).search(query);
  }

  void _positionChanged(Duration value) {
    final beforePosition = position;
    final beforeCaption = currentCaption;
    final beforeSpeaker = currentSpeaker;
    position = value;
    duration = engine.duration;
    playing = engine.playing;
    _recompute();
    if (playing &&
        !isLive &&
        (_lastSave == null || now().difference(_lastSave!) >= saveEvery)) {
      unawaited(_save());
    }
    if (position != beforePosition ||
        currentCaption != beforeCaption ||
        currentSpeaker != beforeSpeaker) {
      notifyListeners();
    }
  }

  void _recompute() {
    duration = engine.duration;
    playing = engine.playing;
    final caps = _captionList;
    final wall = stream == null || detail == null
        ? null
        : detail!.wallClockAt(position, stream!);
    currentCaption = captionsOn && wall != null && caps.isNotEmpty
        ? CaptionIndex(caps).at(wall)
        : null;
    currentSpeaker = null;
    for (final mark in speakers) {
      if (detail != null &&
          stream != null &&
          detail!.offsetOf(mark.wallClock, stream!) <= position) {
        currentSpeaker = mark;
      }
    }
  }

  Future<void> _save() async {
    final row = event;
    final playingStream = stream;
    if (row == null ||
        playingStream == null ||
        playingStream.isLive ||
        detail == null) {
      return;
    }
    await library.saveProgress(
      WatchRecord(
        eventId: row.id,
        title: row.title,
        eventDate: _requestDate ?? row.scheduledStart,
        position: position,
        duration: playingStream.duration ?? duration,
        updatedAt: now(),
      ),
    );
    _lastSave = now();
  }

  DateTime? _requestDate;
  Future<void> close() async {
    await _save();
    for (final s in _subscriptions) {
      await s.cancel();
    }
    await engine.dispose();
  }
}
