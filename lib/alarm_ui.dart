import 'package:flutter/material.dart';

import 'notifs.dart';
import 'pages/alarm_screen.dart';
import 'scheduling/alert_payload.dart';

/// The single way to open the full-screen alarm. A notification tap, a
/// lock-screen full-screen launch and the in-app due-time watcher all come
/// through here, so they cannot stack duplicate alarm screens.
class AlarmUi {
  AlarmUi._();

  /// Reminder id -> notification id of the occurrence on screen.
  static final Map<String, int?> _showing = <String, int?>{};

  static bool isShowing(String reminderId) => _showing.containsKey(reminderId);

  /// Notification IDs whose alarm is on screen right now. The scheduler
  /// treats these like visible notifications and never re-posts them.
  static Set<int> get onScreenNotificationIds => {
    for (final id in _showing.values) ?id,
  };

  static Future<void> show({
    required String reminderId,
    DateTime? occurrence,
  }) async {
    final nav = Notifs.navKey.currentState;
    if (nav == null || _showing.containsKey(reminderId)) return;

    final notificationId = occurrence == null
        ? null
        : stableNotificationId(reminderId, occurrence, AlertKind.alarm);
    _showing[reminderId] = notificationId;

    // The screen plays the alarm itself; stop the ringing notification so the
    // two sounds don't overlap.
    if (notificationId != null) {
      try {
        await Notifs.cancel(notificationId);
      } catch (e) {
        debugPrint('Could not silence alarm notification: $e');
      }
    }

    try {
      await nav.push(
        MaterialPageRoute<void>(
          builder: (_) =>
              AlarmScreen(reminderId: reminderId, occurrence: occurrence),
          fullscreenDialog: true,
        ),
      );
    } finally {
      _showing.remove(reminderId);
    }
  }
}
