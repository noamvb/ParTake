import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parlvu/parlvu.dart';
import 'package:partake/platform/background_audio.dart';
import 'package:partake/player/player_controller.dart';
import 'package:partake/ui/open_request.dart';

import '../fakes.dart';
import '../player/fake_engine.dart';

void main() {
  final detail = parseEventPage(
    File('packages/parlvu/test/fixtures/event_fewo_13596766.html')
        .readAsStringSync(),
    id: 45750,
  );
  final row = ListingEvent(
    id: 45750,
    foreignKey: null,
    title: 'FEWO Meeting',
    description: '',
    location: '',
    scheduledStart: DateTime.utc(2026, 9, 23),
    scheduledEnd: null,
    actualStart: null,
    actualEnd: null,
    status: EventStatus.ended,
    statusCode: -1,
    statusText: '',
  );
  final date = DateTime.utc(2026, 9, 23);

  Future<(PlayerController, FakeEngine)> opened() async {
    final engine = FakeEngine();
    final controller = PlayerController(
      source: FakeEventSource(details: {45750: detail}),
      library: FakeLibrary(),
      engine: engine,
    );
    await controller.open(
      OpenRequest(
        eventId: 45750,
        title: row.title,
        eventDate: date,
        event: row,
      ),
    );
    return (controller, engine);
  }

  test('publishes event metadata and duration', () async {
    final (controller, engine) = await opened();
    final handler = PartakeAudioHandler()
      ..attach(controller, title: 'Fallback');
    engine.emitDuration(const Duration(seconds: 900));
    await Future<void>.delayed(Duration.zero);
    expect(handler.mediaItem.value?.title, 'FEWO Meeting');
    expect(handler.mediaItem.value?.album, 'ParTake');
    expect(handler.mediaItem.value?.duration, const Duration(seconds: 900));
    handler.detach(controller);
    await controller.close();
  });

  test('mirrors playing state and media controls', () async {
    final (controller, engine) = await opened();
    final handler = PartakeAudioHandler()
      ..attach(controller, title: 'Fallback');
    await engine.play();
    await Future<void>.delayed(Duration.zero);
    expect(handler.playbackState.value.playing, isTrue);
    expect(
      handler.playbackState.value.controls[1].androidIcon,
      MediaControl.pause.androidIcon,
    );
    await engine.pause();
    await Future<void>.delayed(Duration.zero);
    expect(handler.playbackState.value.playing, isFalse);
    expect(
      handler.playbackState.value.controls[1].androidIcon,
      MediaControl.play.androidIcon,
    );
    handler.detach(controller);
    await controller.close();
  });

  test('maps rewind, fast forward and seek to controller positions', () async {
    final (controller, engine) = await opened();
    final handler = PartakeAudioHandler()
      ..attach(controller, title: 'Fallback');
    await controller.seek(const Duration(seconds: 100));
    await handler.rewind();
    expect(engine.seeks.last, const Duration(seconds: 70));
    await controller.seek(const Duration(seconds: 100));
    await handler.fastForward();
    expect(engine.seeks.last, const Duration(seconds: 130));
    await handler.seek(const Duration(seconds: 500));
    expect(engine.seeks.last, const Duration(seconds: 500));
    handler.detach(controller);
    await controller.close();
  });

  test('pause is idempotent when already paused', () async {
    final (controller, engine) = await opened();
    final handler = PartakeAudioHandler()
      ..attach(controller, title: 'Fallback');
    await handler.pause();
    expect(engine.pauses, 1);
    await handler.pause();
    expect(engine.pauses, 1);
    handler.detach(controller);
    await controller.close();
  });

  test('throttles position only playback state updates', () async {
    var clock = DateTime.utc(2026);
    final engine = FakeEngine();
    final controller = PlayerController(
      source: FakeEventSource(details: {45750: detail}),
      library: FakeLibrary(),
      engine: engine,
    );
    await controller.open(
      OpenRequest(
        eventId: 45750,
        title: row.title,
        eventDate: date,
        event: row,
      ),
    );
    final handler = PartakeAudioHandler(now: () => clock)
      ..attach(controller, title: 'Fallback');
    var updates = 0;
    final sub = handler.playbackState.listen((_) => updates++);
    for (var i = 1; i <= 10; i++) {
      engine.emitPosition(Duration(seconds: i));
      clock = clock.add(const Duration(milliseconds: 50));
      await Future<void>.delayed(Duration.zero);
    }
    expect(updates, lessThanOrEqualTo(2));
    await sub.cancel();
    handler.detach(controller);
    await controller.close();
  });

  test('detach idles and stops mirroring controller updates', () async {
    final (controller, engine) = await opened();
    final handler = PartakeAudioHandler()
      ..attach(controller, title: 'Fallback');
    await engine.play();
    await Future<void>.delayed(Duration.zero);
    expect(handler.playbackState.value.playing, isTrue);
    handler.detach(controller);
    expect(handler.playbackState.value.playing, isFalse);
    expect(handler.playbackState.value.processingState.name, 'idle');
    final prior = handler.playbackState.value;
    await engine.pause();
    await Future<void>.delayed(Duration.zero);
    expect(handler.playbackState.value, prior);
    await controller.close();
  });
}
