import 'video_ready_stub.dart'
    if (dart.library.js_interop) 'video_ready_web.dart'
    as platform;

/// Call just before reopening a stream. The returned function completes once
/// the page's existing <video> element has gone through its reload and can
/// play again, or after a timeout. Completes at once when there is no
/// element yet (first open) and off the web.
Future<void> Function() armVideoReady() => platform.armVideoReady();
