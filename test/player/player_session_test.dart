import 'package:flutter_test/flutter_test.dart';
import 'package:partake/player/player_session.dart';
import 'package:partake/ui/open_request.dart';

import '../fakes.dart';
import 'audio_variants.dart';
import 'fake_engine.dart';
import 'fake_live_captions.dart';

void main() {
  Future<(PlayerSession, FakeEngine)> opened({
    required bool resumeAfterMove,
  }) async {
    final engine = FakeEngine();
    final session = PlayerSession(
      request: OpenRequest(
        eventId: 45750,
        title: 'FEWO Meeting',
        eventDate: DateTime.utc(2026, 9, 23),
      ),
      source: FakeEventSource(details: {45750: audioVideoDetail()}),
      library: FakeLibrary(),
      engineFactory: () => engine,
      liveCaptionsFactory: FakeLiveCaptions.new,
      resumeAfterMove: resumeAfterMove,
    );
    await Future<void>.delayed(Duration.zero);
    addTearDown(session.close);
    expect(session.controller.playing, isTrue);
    return (session, engine);
  }

  test('playback that stops right after minimize resumes on the web', () async {
    final (session, engine) = await opened(resumeAfterMove: true);
    session.minimize();
    await engine.pause();
    await Future<void>.delayed(Duration.zero);
    expect(engine.plays, 1);
    expect(engine.playing, isTrue);

    // Only the stop that follows the move: a later pause is the user's.
    await engine.pause();
    await Future<void>.delayed(Duration.zero);
    expect(engine.plays, 1);
    expect(engine.playing, isFalse);
  });

  test('without the web guard a pause after minimize stays paused', () async {
    final (session, engine) = await opened(resumeAfterMove: false);
    session.minimize();
    await engine.pause();
    await Future<void>.delayed(Duration.zero);
    expect(engine.plays, 0);
    expect(engine.playing, isFalse);
  });
}
