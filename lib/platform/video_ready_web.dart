import 'package:web/web.dart' as web;

web.HTMLVideoElement? _video() =>
    web.document.querySelector('video') as web.HTMLVideoElement?;

// HAVE_FUTURE_DATA (3): attached and able to start playing.
bool _ready(web.HTMLVideoElement? v) =>
    v != null && v.isConnected && v.readyState >= 3;

Future<void> Function() armVideoReady() {
  if (_video() == null) return () async {};
  return () async {
    final start = DateTime.now();
    var reloading = false;
    while (DateTime.now().difference(start) < const Duration(seconds: 15)) {
      final ready = _ready(_video());
      if (!ready) reloading = true;
      if (ready && reloading) return;
      // Never saw a reload: the element was reused without one.
      if (!reloading &&
          DateTime.now().difference(start) > const Duration(seconds: 2)) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  };
}
