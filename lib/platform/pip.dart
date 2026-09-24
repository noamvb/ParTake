import 'pip_stub.dart'
    if (dart.library.io) 'pip_android.dart'
    if (dart.library.js_interop) 'pip_web.dart'
    as platform;

abstract class PipControl {
  bool get available;
  Stream<bool> get active;
  Future<void> enter();
  Future<void> setAutoEnter(bool on);
}

PipControl createPipControl() => platform.createPipControl();
