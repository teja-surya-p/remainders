import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Showing over the lock screen is switched on natively only when an alarm
/// launches the app (MainActivity), so the rest of the app is never usable
/// on a locked phone. The alarm screen turns it off again when it closes.
class LockScreen {
  LockScreen._();

  static const MethodChannel _channel = MethodChannel('snooze/lockscreen');

  static Future<void> release() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>('release');
    } catch (e) {
      debugPrint('LockScreen.release failed: $e');
    }
  }
}
