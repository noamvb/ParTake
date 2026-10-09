import 'pip.dart';

PipControl createPipControl() => _StubPipControl();

class _StubPipControl implements PipControl {
  @override
  bool get available => false;

  @override
  Stream<bool> get active => const Stream<bool>.empty();

  @override
  Stream<PipAction> get actions => const Stream<PipAction>.empty();

  @override
  Future<void> setPlaying(bool playing) async {}

  @override
  Future<void> closeWindow() async {}

  @override
  Future<void> enter() async {}

  @override
  Future<void> setAutoEnter(bool on) async {}
}
