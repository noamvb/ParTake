import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'live_captions.dart';

extension type _CaptionTextCue(JSObject _) implements JSObject {
  external String get text;
}

LiveCaptionFeed createLiveCaptionFeed() => _WebLiveCaptionFeed();

class _WebLiveCaptionFeed implements LiveCaptionFeed {
  final _texts = StreamController<String?>.broadcast();
  final Map<web.TextTrack, JSFunction> _listeners = {};
  web.HTMLVideoElement? _video;
  Timer? _timer;
  String? _lastText;

  _WebLiveCaptionFeed() {
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) => _poll());
    _poll();
  }

  @override
  Stream<String?> get text => _texts.stream;

  void _poll() {
    final found = web.document.querySelector('video') as web.HTMLVideoElement?;
    if (_video != found || (_video != null && !_video!.isConnected)) {
      for (final entry in _listeners.entries) {
        entry.key.removeEventListener('cuechange', entry.value);
      }
      _listeners.clear();
      _video = found;
    }
    final video = _video;
    if (video == null) return;
    final tracks = video.textTracks;
    web.TextTrack? firstCaptions;
    for (var i = 0; i < tracks.length; i++) {
      final track = tracks[i];
      if (track.kind != 'captions' && track.kind != 'subtitles') continue;
      if (track.mode == 'disabled') track.mode = 'hidden';
      if (track.kind == 'captions' && firstCaptions == null) {
        firstCaptions = track;
      }
      if (!_listeners.containsKey(track)) {
        final listener = ((web.Event _) => _emitActive(
          _captionsTrack(video),
        )).toJS;
        _listeners[track] = listener;
        track.addEventListener('cuechange', listener);
      }
    }
    _emitActive(firstCaptions);
  }

  web.TextTrack? _captionsTrack(web.HTMLVideoElement video) {
    final tracks = video.textTracks;
    for (var i = 0; i < tracks.length; i++) {
      final track = tracks[i];
      if (track.kind == 'captions') return track;
    }
    return null;
  }

  void _emitActive(web.TextTrack? track) {
    final cues = track?.activeCues;
    final lines = <String>[];
    if (cues != null) {
      for (var i = 0; i < cues.length; i++) {
        final line = (_CaptionTextCue(cues[i] as JSObject).text).trim();
        if (line.isNotEmpty) lines.add(line);
      }
    }
    final value = lines.isEmpty ? null : lines.join('\n');
    if (value == _lastText) return;
    _lastText = value;
    if (!_texts.isClosed) _texts.add(value);
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final entry in _listeners.entries) {
      entry.key.removeEventListener('cuechange', entry.value);
    }
    _listeners.clear();
    unawaited(_texts.close());
  }
}
