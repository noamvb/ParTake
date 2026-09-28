import 'dart:async';

import 'package:floating/floating.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'pip.dart';

PipControl createPipControl() => _AndroidPipControl();

class _AndroidPipControl implements PipControl {
  final Floating _floating = Floating();
  static const _channel = MethodChannel('partake/pip');

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
    // MainActivity enters PiP itself when the user leaves the app; the
    // auto-enter flag below adds the smooth home-gesture animation on 12+.
    await _channel.invokeMethod<void>('setPipOnLeave', on);
    try {
      if (on) {
        await _floating.enable(const OnLeavePiP(aspectRatio: Rational(16, 9)));
      } else {
        await _floating.cancelOnLeavePiP();
      }
    } on PlatformException {
      // Android 8-11 has no auto-enter flag; MainActivity covers it.
    }
  }
}
