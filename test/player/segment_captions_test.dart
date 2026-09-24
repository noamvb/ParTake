import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:parlvu/parlvu.dart';
import 'package:partake/player/player_screen.dart';
import 'package:partake/player/segment_captions.dart';

import 'fake_engine.dart';

void main() {
  final fixture = Uint8List.fromList(
    File('packages/parlvu/test/fixtures/live_cc_en_39007_39023.ts')
        .readAsBytesSync(),
  );
  const master = 'https://example.test/VL/EN/Playlist.m3u8?DVR&ContentEntity=1';
  String playlist(int count, {int first = 1}) =>
      '#EXTM3U\n#EXT-X-MEDIA-SEQUENCE:1\n'
      '${List.generate(count, (i) => '#EXTINF:10.01,\ns${first + i}.ts').join('\n')}\n';

  test('takes last five initially, then fetches only new segments', () async {
    var first = 1;
    var count = 6;
    final paths = <String, int>{};
    final client = MockClient((request) async {
      paths.update(request.url.path, (v) => v + 1, ifAbsent: () => 1);
      if (request.url.path.endsWith('Playlist.m3u8')) {
        return http.Response(
          '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1\nchunklist.m3u8\n',
          200,
        );
      }
      if (request.url.path.endsWith('chunklist.m3u8')) {
        return http.Response(playlist(count, first: first), 200);
      }
      return http.Response.bytes(fixture, 200);
    });
    final feed = SegmentCaptionFeed(
      engine: FakeEngine(),
      client: client,
      pollEvery: const Duration(milliseconds: 30),
      tickEvery: const Duration(hours: 1),
    );
    feed.follow(Uri.parse(master));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(paths.values.fold(0, (a, b) => a + b), 7);
    count++;
    first++;
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(paths['/VL/EN/s1.ts'], isNull);
    expect(paths['/VL/EN/s2.ts'], 1);
    expect(paths['/VL/EN/s7.ts'], 1);
    feed.dispose();
  });

  test('whole-window playback fetches segments at the playhead', () async {
    final paths = <String>[];
    final client = MockClient((request) async {
      paths.add(request.url.path);
      if (request.url.path.endsWith('Playlist.m3u8')) {
        return http.Response(
          '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1\nchunklist.m3u8\n',
          200,
        );
      }
      if (request.url.path.endsWith('chunklist.m3u8')) {
        return http.Response(
          playlist(10).replaceFirst(
            '#EXT-X-MEDIA-SEQUENCE:1\n',
            '#EXT-X-MEDIA-SEQUENCE:1\n#STARTTIME:2026-09-24T08:00:00Z\n',
          ),
          200,
        );
      }
      return http.Response.bytes(fixture, 200);
    });
    // The playhead is 25 s into a window that starts 20 s before the SD
    // playlist's: 08:00:05, inside s1 (08:00:00-08:00:10.01).
    final engine = FakeEngine()
      ..windowStart = DateTime.utc(2026, 9, 24, 7, 59, 40)
      ..currentPosition = const Duration(seconds: 25);
    final feed = SegmentCaptionFeed(
      engine: engine,
      client: client,
      pollEvery: const Duration(hours: 1),
      tickEvery: const Duration(hours: 1),
    );
    feed.follow(Uri.parse(master));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final segments = paths.where((p) => p.endsWith('.ts')).toList();
    expect(segments, ['/VL/EN/s1.ts', '/VL/EN/s2.ts', '/VL/EN/s3.ts']);
    feed.dispose();
  });

  test('selects decoded caption by raw media clock', () async {
    final decoder = Cea608Decoder();
    final changes = <CaptionChange>[];
    for (final pair in extractCcPairs(
      fixture,
    ).where((pair) => pair.field == 0)) {
      final change = decoder.push(pair.pts, pair.b1, pair.b2);
      if (change != null) changes.add(change);
    }
    expect(changes, isNotEmpty);
    final engine = FakeEngine()..clock = changes.first.pts / 90000 - 1;
    final client = MockClient(
      (request) async => request.url.path.endsWith('Playlist.m3u8')
          ? http.Response(
              '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1\nchunklist.m3u8\n',
              200,
            )
          : request.url.path.endsWith('chunklist.m3u8')
          ? http.Response(playlist(1), 200)
          : http.Response.bytes(fixture, 200),
    );
    final feed = SegmentCaptionFeed(
      engine: engine,
      client: client,
      pollEvery: const Duration(seconds: 1),
      tickEvery: const Duration(milliseconds: 10),
    );
    final emitted = <String?>[];
    final sub = feed.text.listen(emitted.add);
    feed.follow(Uri.parse(master));
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(emitted, [null]);
    engine.clock = changes.last.pts / 90000 + .01;
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(emitted, contains(changes.last.text));
    feed.dispose();
    await sub.cancel();
  });

  test('follow null emits null and stops requests', () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      return http.Response(
        '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1\nchunklist.m3u8\n',
        200,
      );
    });
    final feed = SegmentCaptionFeed(
      engine: FakeEngine(),
      client: client,
      pollEvery: const Duration(milliseconds: 10),
      tickEvery: const Duration(hours: 1),
    );
    final emitted = <String?>[];
    final sub = feed.text.listen(emitted.add);
    feed.follow(Uri.parse(master));
    await Future<void>.delayed(const Duration(milliseconds: 3));
    feed.follow(null);
    final stoppedAt = requests;
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(requests, stoppedAt);
    expect(emitted.last, isNull);
    feed.dispose();
    await sub.cancel();
  });

  test('chunklist HTTP 500 is skipped without caption emission', () async {
    final client = MockClient(
      (request) async => request.url.path.endsWith('Playlist.m3u8')
          ? http.Response(
              '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1\nchunklist.m3u8\n',
              200,
            )
          : http.Response('failed', 500),
    );
    final feed = SegmentCaptionFeed(
      engine: FakeEngine(),
      client: client,
      pollEvery: const Duration(milliseconds: 10),
      tickEvery: const Duration(hours: 1),
    );
    final emitted = <String?>[];
    final sub = feed.text.listen(emitted.add);
    feed.follow(Uri.parse(master));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(emitted, [null]);
    feed.dispose();
    await sub.cancel();
  });
  test('off the web the default live caption feed decodes segments', () {
    final feed = defaultLiveCaptionFeed(FakeEngine());
    expect(feed, isA<SegmentCaptionFeed>());
    feed.dispose();
  });
}
