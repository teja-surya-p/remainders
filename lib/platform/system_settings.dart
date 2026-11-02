import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Facts about the phone that decide whether alarms ring on time.
class DeviceStatus {
  const DeviceStatus({
    required this.manufacturer,
    required this.batteryUnrestricted,
    required this.fullScreenAllowed,
  });

  /// Lower-case maker name, e.g. "samsung", "xiaomi", "google".
  final String manufacturer;

  /// Snooze is exempt from battery optimisation.
  final bool batteryUnrestricted;

  /// Alarms may open full screen over the lock screen (Android 14+ asks).
  final bool fullScreenAllowed;

  static const unknown = DeviceStatus(
    manufacturer: '',
    batteryUnrestricted: true,
    fullScreenAllowed: true,
  );
}

enum SettingsPage { notifications, exactAlarms, fullScreen, battery }

/// Android settings pages and device facts (MainActivity, "snooze/system").
class SystemSettings {
  SystemSettings._();

  static const MethodChannel _channel = MethodChannel('snooze/system');

  static Future<DeviceStatus> status() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return DeviceStatus.unknown;
    }
    try {
      final map = await _channel.invokeMapMethod<String, Object?>('status');
      if (map == null) return DeviceStatus.unknown;
      return DeviceStatus(
        manufacturer: (map['manufacturer'] as String?) ?? '',
        batteryUnrestricted: map['batteryUnrestricted'] == true,
        fullScreenAllowed: map['fullScreenAllowed'] != false,
      );
    } catch (e) {
      debugPrint('Device status unavailable: $e');
      return DeviceStatus.unknown;
    }
  }

  /// Opens the page; false if no settings screen could be opened.
  static Future<bool> open(SettingsPage page) async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      return await _channel.invokeMethod<bool>('open', {'page': page.name}) ??
          false;
    } catch (e) {
      debugPrint('Opening ${page.name} settings failed: $e');
      return false;
    }
  }
}
