import 'dart:io';

import 'package:vibration/vibration.dart';

class AlarmVibration {
  AlarmVibration._();

  static bool _started = false;

  static Future<void> start() async {
    if (_started) return;
    _started = true;

    final hasVibrator = await Vibration.hasVibrator();
    if (!hasVibrator) return;

    if (Platform.isAndroid) {
      Vibration.vibrate(pattern: [0, 1000, 500, 1000], repeat: 1);
    } else {
      Vibration.vibrate(pattern: [0, 500, 500, 500], repeat: 1);
    }
  }

  static Future<void> stop() async {
    if (!_started) return;
    _started = false;
    final hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator) Vibration.cancel();
  }
}
