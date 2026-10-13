import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:parlvu/parlvu.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'alerts/alert_runtime.dart';
import 'app.dart';
import 'platform/background_audio.dart';
import 'services/parlvu_event_source.dart';
import 'services/prefs_library.dart';
import 'ui/open_request.dart';
import 'watch/watch_alerts.dart';
import 'watch/watch_follows.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final library = PrefsLibrary(prefs);
  final watch = WatchFollows(
    prefs: prefs,
    library: library,
    defaultAddress: kIsWeb ? Uri.base.origin : deckDefaultAddress,
  );
  final source = ParlVuEventSource(
    // In the browser ParlVU is only reachable through the home server's
    // same-origin proxy (ParlVU sends no CORS headers); see server/.
    parlvu: ParlVuClient(baseUri: kIsWeb ? Uri.base.resolve('/parlvu') : null),
    openParliament: OpenParliamentClient(),
  );

  final opens = StreamController<OpenRequest>.broadcast();
  OpenRequest fromAlert(int eventId) => OpenRequest(
    eventId: eventId,
    title: 'Live proceedings',
    eventDate: parliamentDate(DateTime.now()),
  );

  await AlertRuntime.initialize();
  AlertRuntime.tappedEventIds.listen((id) => opens.add(fromAlert(id)));
  final audioHandler = await initBackgroundAudio();

  runApp(
    PartakeApp(
      source: source,
      library: library,
      watch: watch,
      openRequests: opens.stream,
      audioHandler: audioHandler,
    ),
  );

  // After the first frame so the navigator exists; no-ops off Android.
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    unawaited(watch.sync());
    final launched = await AlertRuntime.launchEventId();
    if (launched != null) opens.add(fromAlert(launched));
    await AlertRuntime.requestPermission();
  });
}
