import 'pip_stub.dart'
    if (dart.library.io) 'pip_android.dart'
    if (dart.library.js_interop) 'pip_web.dart'
    as platform;

/// A button the user pressed in the system PiP window, or its dismissal.
enum PipAction { audioOnly, playPause, dismissed }

abstract class PipControl {
  bool get available;
  Stream<bool> get active;

  /// Actions from the system PiP window: its buttons, and its dismissal.
  Stream<PipAction> get actions;

  /// Tells the PiP window whether playback is running, so it shows pause or play.
  Future<void> setPlaying(bool playing);

  /// Closes the system PiP window, leaving playback running in the background.
  Future<void> closeWindow();
  Future<void> enter();
  Future<void> setAutoEnter(bool on);
}

PipControl createPipControl() => platform.createPipControl();
