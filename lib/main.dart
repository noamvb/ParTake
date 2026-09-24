import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:parlvu/parlvu.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'alerts/alert_runtime.dart';
import 'app.dart';
import 'services/parlvu_event_source.dart';
import 'services/prefs_library.dart';
import 'ui/open_request.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
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

  runApp(
    PartakeApp(
      source: source,
      library: PrefsLibrary(prefs),
      openRequests: opens.stream,
    ),
  );

  // After the first frame so the navigator exists; no-ops off Android.
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    final launched = await AlertRuntime.launchEventId();
    if (launched != null) opens.add(fromAlert(launched));
    await AlertRuntime.requestPermission();
  });
}
