import 'dart:async';

import 'package:floating/floating.dart';
import 'package:flutter/foundation.dart';

import 'pip.dart';

PipControl createPipControl() => _AndroidPipControl();

class _AndroidPipControl implements PipControl {
  final Floating _floating = Floating();

  @override
  bool get available => defaultTargetPlatform == TargetPlatform.android;

  @override
  Stream<bool> get active =>
      _floating.pipStatusStream.map((status) => status == PiPStatus.enabled);

  @override
  Future<void> enter() async {
    await _floating.enable(const ImmediatePiP(aspectRatio: Rational(16, 9)));
  }

  @override
  Future<void> setAutoEnter(bool on) async {
    if (on) {
      await _floating.enable(const OnLeavePiP(aspectRatio: Rational(16, 9)));
    } else {
      await _floating.cancelOnLeavePiP();
    }
  }
}
