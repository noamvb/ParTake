import 'package:flutter_test/flutter_test.dart';
import 'package:partake/player/live_playlist.dart';
import 'package:partake/player/media_engine.dart';

void main() {
  final base = Uri.parse(
    'https://cdn.test/HOC/VH/FL/chunklist.m3u8?DVR&ContentEntity=1',
  );
  // Shape of a ParlVU live chunklist (2026-09-24): no PLAYLIST-TYPE, no
  // ENDLIST, #STARTTIME is the wall clock of the first segment.
  const upstream =
      '#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-ALLOW-CACHE:NO\n'
      '#EXT-X-TARGETDURATION:12\n#EXT-X-MEDIA-SEQUENCE:100\n'
      '#SESSIONTIME:2026-09-20T07:00:57Z\n#STARTTIMESTAMP:0\n'
      '#STARTTIME:2026-09-24T07:41:38Z\n\n'
      '#EXTINF:10.01,\ns_101.ts\n#EXTINF:10.01,\ns_102.ts\n'
      '#EXTINF:9.98,\ns_103.ts\n';
  // One minute later the window slid by one segment.
  const slid =
      '#EXTM3U\n#EXT-X-TARGETDURATION:12\n#EXT-X-MEDIA-SEQUENCE:101\n'
      '#STARTTIME:2026-09-24T07:41:48Z\n'
      '#EXTINF:10.01,\ns_102.ts\n#EXTINF:9.98,\ns_103.ts\n'
      '#EXTINF:10.01,\ns_104.ts\n';

  test('re-serves a live chunklist as an EVENT playlist, exact text', () {
    final playlist = LivePlaylist()..merge(upstream, base);
    expect(
      playlist.render(),
      '#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-PLAYLIST-TYPE:EVENT\n'
      '#EXT-X-TARGETDURATION:12\n#EXT-X-MEDIA-SEQUENCE:100\n'
      '#EXTINF:10.010,\nhttps://cdn.test/HOC/VH/FL/s_101.ts\n'
      '#EXTINF:10.010,\nhttps://cdn.test/HOC/VH/FL/s_102.ts\n'
      '#EXTINF:9.980,\nhttps://cdn.test/HOC/VH/FL/s_103.ts\n',
    );
    expect(playlist.edge, const Duration(milliseconds: 30000));
    expect(playlist.windowStart, DateTime.utc(2026, 9, 24, 7, 41, 38));
  });

  test('a slid window appends new segments and keeps the old ones', () {
    final playlist = LivePlaylist()
      ..merge(upstream, base)
      ..merge(slid, base);
    expect(playlist.length, 4);
    final text = playlist.render();
    expect(text, contains('#EXT-X-MEDIA-SEQUENCE:100\n'));
    expect(text, contains('s_101.ts'));
    expect(text.indexOf('s_104.ts'), greaterThan(text.indexOf('s_103.ts')));
    expect('s_103.ts'.allMatches(text).length, 1);
    expect(playlist.edge, const Duration(milliseconds: 40010));
    expect(playlist.windowStart, DateTime.utc(2026, 9, 24, 7, 41, 38));
  });

  test('only a live media playlist is proxied', () {
    expect(LivePlaylist.isLiveMedia(upstream), isTrue);
    expect(LivePlaylist.isLiveMedia('$upstream#EXT-X-ENDLIST\n'), isFalse);
    expect(
      LivePlaylist.isLiveMedia(
        upstream.replaceFirst(
          '#EXTM3U\n',
          '#EXTM3U\n#EXT-X-PLAYLIST-TYPE:VOD\n',
        ),
      ),
      isFalse,
    );
    const master =
        '#EXTM3U\n#EXT-X-VERSION:3\n'
        '#EXT-X-STREAM-INF:BANDWIDTH=2564000,RESOLUTION=1920x1080\n'
        'chunklist.m3u8\n';
    expect(LivePlaylist.isLiveMedia(master), isFalse);
    expect(
      LivePlaylist.firstVariant(
        master,
        Uri.parse('https://cdn.test/HOC/VH/FL/Playlist.m3u8?DVR'),
      ),
      Uri.parse('https://cdn.test/HOC/VH/FL/chunklist.m3u8'),
    );
    expect(LivePlaylist.firstVariant(upstream, base), isNull);
  });

  group('liveStartPosition', () {
    const edge = Duration(seconds: 46800);
    test('opens 36 s short of the edge by default', () {
      expect(liveStartPosition(edge: edge), const Duration(seconds: 46764));
    });
    test('a language switch keeps the wall clock across windows', () {
      expect(
        liveStartPosition(
          edge: edge,
          requested: const Duration(seconds: 23400),
          previousWindowStart: DateTime.utc(2026, 9, 24, 7, 57, 49),
          windowStart: DateTime.utc(2026, 9, 24, 7, 58, 9),
        ),
        const Duration(seconds: 23380),
      );
    });
    test('clamps into the window', () {
      expect(
        liveStartPosition(edge: edge, requested: const Duration(hours: 20)),
        const Duration(seconds: 46764),
      );
      expect(
        liveStartPosition(
          edge: edge,
          requested: const Duration(seconds: 5),
          previousWindowStart: DateTime.utc(2026, 9, 24, 7),
          windowStart: DateTime.utc(2026, 9, 24, 7, 1),
        ),
        Duration.zero,
      );
    });
  });
}
