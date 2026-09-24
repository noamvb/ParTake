import 'dart:async';

import 'package:partake/platform/pip.dart';

class FakePip implements PipControl {
  FakePip({required this.available});

  @override
  final bool available;
  final states = StreamController<bool>.broadcast(sync: true);
  int enterCalls = 0;
  final autoEnterCalls = <bool>[];

  @override
  Stream<bool> get active => states.stream;

  @override
  Future<void> enter() async {
    enterCalls++;
  }

  @override
  Future<void> setAutoEnter(bool on) async {
    autoEnterCalls.add(on);
  }
}
