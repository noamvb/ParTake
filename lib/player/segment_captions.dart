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
      final lines = response.body
          .split(RegExp(r'\r?\n'))
          .map((s) => s.trim())
          .toList();
      final segments = <Uri>[];
      for (var i = 0; i < lines.length; i++) {
        final value = lines[i];
        if (value.isNotEmpty && !value.startsWith('#')) {
          segments.add(chunklist.resolve(value));
        }
      }
      final pending = _hasPolled
          ? segments.where((u) => !_seen.contains(u.toString())).toList()
          : segments
                .skip(segments.length > 5 ? segments.length - 5 : 0)
                .toList();
      _hasPolled = true;
      for (final uri in pending) {
        if (_disposed || generation != _generation) return;
        final segment = await _client.get(uri, headers: _headers);
        if (_disposed || generation != _generation) return;
        if (segment.statusCode < 200 || segment.statusCode >= 300) {
          continue;
        }
        _seen.add(uri.toString());
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
    String? value;
    for (final change in _changes) {
      if (_signedDelta(change.pts, pts) <= 0) value = change.text;
    }
    if (value == _emitted) return;
    _emitted = value;
    _text.add(value);
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
