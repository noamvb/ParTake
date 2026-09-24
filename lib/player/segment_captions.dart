import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:parlvu/parlvu.dart';

import '../platform/live_captions.dart';
import 'media_engine.dart';

class SegmentCaptionFeed implements LiveCaptionFeed, FollowsCaptionStream {
  SegmentCaptionFeed({
    required this.engine,
    http.Client? client,
    this.pollEvery = const Duration(seconds: 5),
    this.tickEvery = const Duration(milliseconds: 250),
  }) : _client = client ?? http.Client() {
    _tick = Timer.periodic(tickEvery, (_) => unawaited(_emitForClock()));
  }

  final MediaEngine engine;
  final http.Client _client;
  final Duration pollEvery;
  final Duration tickEvery;
  final _text = StreamController<String?>.broadcast();
  final List<CaptionChange> _changes = [];
  final Set<String> _seen = {};
  late final Timer _tick;
  Timer? _poll;
  Uri? _master;
  Uri? _chunklist;
  Cea608Decoder _decoder = Cea608Decoder();
  bool _disposed = false;
  bool _polling = false;
  bool _hasPolled = false;
  int? _lastIndex;
  int _generation = 0;
  String? _emitted;

  @override
  Stream<String?> get text => _text.stream;

  @override
  void follow(Uri? sdMasterUrl) {
    if (_disposed) return;
    if (sdMasterUrl == _master) {
      if (sdMasterUrl == null) _text.add(null);
      return;
    }
    _generation++;
    _master = sdMasterUrl;
    _poll?.cancel();
    _chunklist = null;
    _changes.clear();
    _seen.clear();
    _decoder = Cea608Decoder();
    _hasPolled = false;
    _lastIndex = null;
    _emitted = null;
    _text.add(null);
    if (sdMasterUrl == null) return;
    unawaited(_pollOnce());
    _poll = Timer.periodic(pollEvery, (_) => unawaited(_pollOnce()));
  }

  static const _headers = {
    'User-Agent': 'ParTake/0.1 (+https://github.com/noamvb/ParTake; personal, non-commercial)',
  };

  Future<void> _pollOnce() async {
    if (_disposed || _master == null || _polling) return;
    final generation = _generation;
    final master = _master!;
    _polling = true;
    try {
      var chunklist = _chunklist;
      if (chunklist == null) {
        final masterResponse = await _client.get(master, headers: _headers);
        if (_disposed || generation != _generation) return;
        if (masterResponse.statusCode < 200 ||
            masterResponse.statusCode >= 300) {
          return;
        }
        final line = masterResponse.body
            .split(RegExp(r'\r?\n'))
            .map((s) => s.trim())
            .firstWhere(
              (s) => s.isNotEmpty && !s.startsWith('#'),
              orElse: () => '',
            );
        if (line.isEmpty) return;
        chunklist = master.resolve(line);
        _chunklist = chunklist;
      }
      final response = await _client.get(chunklist, headers: _headers);
      if (_disposed || generation != _generation) return;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return;
      }
      final segments = _parseSegments(response.body, chunklist);
      final anchor = engine.liveWindowStart;
      final List<_Segment> pending;
      if (anchor != null &&
          segments.isNotEmpty &&
          segments.first.start != null) {
        // Whole-window playback (Android): fetch the segments around the
        // playhead, found by wall clock, instead of the newest ones.
        final wall = anchor.add(engine.position);
        var at = 0;
        for (var i = 0; i < segments.length; i++) {
          if (!segments[i].start!.isAfter(wall)) at = i;
        }
        final from = at > 0 ? at - 1 : 0;
        final to = at + 3 < segments.length ? at + 3 : segments.length;
        pending = segments
            .sublist(from, to)
            .where((s) => !_seen.contains(s.uri.toString()))
            .toList();
      } else {
        pending = _hasPolled
            ? segments.where((s) => !_seen.contains(s.uri.toString())).toList()
            : segments
                  .skip(segments.length > 5 ? segments.length - 5 : 0)
                  .toList();
      }
      _hasPolled = true;
      for (final next in pending) {
        final uri = next.uri;
        if (_disposed || generation != _generation) return;
        final segment = await _client.get(uri, headers: _headers);
        if (_disposed || generation != _generation) return;
        if (segment.statusCode < 200 || segment.statusCode >= 300) {
          continue;
        }
        _seen.add(uri.toString());
        // Captions span segments; a decoder fed a segment that does not
        // follow the last one would join unrelated text.
        if (_lastIndex != null && next.index != _lastIndex! + 1) {
          _decoder = Cea608Decoder();
        }
        _lastIndex = next.index;
        for (final pair in extractCcPairs(
          Uint8List.fromList(segment.bodyBytes),
        )) {
          if (pair.field != 0) continue;
          final change = _decoder.push(pair.pts, pair.b1, pair.b2);
          if (change != null) {
            _changes.add(change);
            if (_changes.length > 600) {
              _changes.removeRange(0, _changes.length - 600);
            }
          }
        }
      }
    } catch (_) {
      // A transient HTTP or parsing failure skips this poll.
    } finally {
      _polling = false;
    }
  }

  Future<void> _emitForClock() async {
    if (_disposed || _master == null) return;
    final clock = await engine.mediaClock();
    if (_disposed || clock == null) return;
    final pts = (clock * 90000).round();
    // Segments arrive out of order after a seek: take the latest change at
    // or before the clock, not the last one fetched.
    String? value;
    int? best;
    for (final change in _changes) {
      final delta = _signedDelta(change.pts, pts);
      if (delta <= 0 && (best == null || delta >= best)) {
        best = delta;
        value = change.text;
      }
    }
    if (value == _emitted) return;
    _emitted = value;
    _text.add(value);
  }

  /// Segments of media playlist [text], with ParlVU's `#STARTTIME:` wall
  /// clock, when present, carried forward by `#EXTINF` durations.
  static List<_Segment> _parseSegments(String text, Uri base) {
    final out = <_Segment>[];
    DateTime? wall;
    var sequence = 0;
    Duration? length;
    for (final raw in text.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#STARTTIME:')) {
        wall = DateTime.tryParse(line.substring(11).trim());
      } else if (line.startsWith('#EXT-X-MEDIA-SEQUENCE:')) {
        sequence = int.tryParse(line.substring(22).trim()) ?? 0;
      } else if (line.startsWith('#EXTINF:')) {
        final seconds = double.tryParse(line.substring(8).split(',').first);
        length = seconds == null
            ? null
            : Duration(microseconds: (seconds * 1e6).round());
      } else if (!line.startsWith('#')) {
        out.add(_Segment(sequence++, base.resolve(line), wall));
        wall = wall == null || length == null ? null : wall.add(length);
        length = null;
      }
    }
    return out;
  }

  static const _ptsModulus = 1 << 33;
  static int _signedDelta(int value, int reference) {
    final delta = (value - reference) % _ptsModulus;
    final normalized = delta < 0 ? delta + _ptsModulus : delta;
    return normalized >= _ptsModulus ~/ 2
        ? normalized - _ptsModulus
        : normalized;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _tick.cancel();
    _poll?.cancel();
    _client.close();
    _text.close();
  }
}

class _Segment {
  const _Segment(this.index, this.uri, this.start);
  final int index;
  final Uri uri;
  final DateTime? start;
}
