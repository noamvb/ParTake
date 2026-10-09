import 'dart:async';

import 'package:partake/platform/pip.dart';

class FakePip implements PipControl {
  FakePip({required this.available});

  @override
  final bool available;
  final states = StreamController<bool>.broadcast(sync: true);
  final actionsController = StreamController<PipAction>.broadcast(sync: true);
  final setPlayingCalls = <bool>[];
  int closeWindowCalls = 0;
  int enterCalls = 0;
  final autoEnterCalls = <bool>[];

  @override
  Stream<bool> get active => states.stream;

  @override
  Stream<PipAction> get actions => actionsController.stream;

  @override
  Future<void> setPlaying(bool playing) async {
    setPlayingCalls.add(playing);
  }

  @override
  Future<void> closeWindow() async {
    closeWindowCalls++;
  }

  @override
  Future<void> enter() async {
    enterCalls++;
  }

  @override
  Future<void> setAutoEnter(bool on) async {
    autoEnterCalls.add(on);
  }
}
