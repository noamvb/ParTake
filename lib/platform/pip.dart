import 'pip_stub.dart'
    if (dart.library.io) 'pip_android.dart'
    if (dart.library.js_interop) 'pip_web.dart'
    as platform;

abstract class PipControl {
  bool get available;
  Stream<bool> get active;

  /// Fires when the user taps the headphones action in the system PiP window.
  Stream<void> get audioOnlyRequests;

  /// Closes the system PiP window, leaving playback running in the background.
  Future<void> closeWindow();
  Future<void> enter();
  Future<void> setAutoEnter(bool on);
}

PipControl createPipControl() => platform.createPipControl();
