import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'pages/alarm_screen.dart';
import 'app_services.dart';
import 'firebase_options.dart';
import 'notifs.dart';
import 'pages/snooze_screen.dart';

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) async {
  await SnoozeHandler.handle(response, openCustomUi: false);
}

class SnoozeHandler {
  static Future<void> handle(
    NotificationResponse response, {
    required bool openCustomUi,
  }) async {
    WidgetsFlutterBinding.ensureInitialized();

    final parsed = _parsePayload(response.payload);
    if (parsed == null) return;

    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    await AppServices.initialize();

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await AppServices.bindUser(user);

    final reminderId = parsed.reminderId;
    final action = response.actionId ?? '';

    if (action.isEmpty) {
      if (openCustomUi && parsed.isAlarm) {
        final nav = Notifs.navKey.currentState;
        if (nav != null) {
          nav.push(
            MaterialPageRoute(
              builder: (_) => AlarmScreen(reminderId: reminderId),
            ),
          );
        }
      }
      return;
    }

    if (action == Notifs.aSnooze5) {
      await AppServices.reminders.snoozeReminder(
        reminderId,
        DateTime.now().add(const Duration(minutes: 5)),
      );
      return;
    }

    if (action == Notifs.aSnooze10) {
      await AppServices.reminders.snoozeReminder(
        reminderId,
        DateTime.now().add(const Duration(minutes: 10)),
      );
      return;
    }

    if (action == Notifs.aSnooze30) {
      await AppServices.reminders.snoozeReminder(
        reminderId,
        DateTime.now().add(const Duration(minutes: 30)),
      );
      return;
    }

    if (action == Notifs.aCustom) {
      final input = (response.input ?? '').trim();
      if (input.isNotEmpty) {
        final custom = SnoozeParse.parseCustom(input);
        if (custom != null) {
          await AppServices.reminders.snoozeReminder(reminderId, custom);
          return;
        }
      }

      if (openCustomUi) {
        final nav = Notifs.navKey.currentState;
        if (nav != null) {
          nav.push(
            MaterialPageRoute(
              builder: (_) => SnoozeScreen(reminderId: reminderId),
            ),
          );
        }
      }
      return;
    }

    if (action == Notifs.aDismiss) {
      await AppServices.reminders.dismissReminder(reminderId);
      return;
    }
  }
}

class SnoozeParse {
  static DateTime? parseCustom(String input) {
    final s = input.trim();
    if (s.isEmpty) return null;

    final mins = int.tryParse(s);
    if (mins != null && mins > 0) {
      return DateTime.now().add(Duration(minutes: mins));
    }

    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(s);
    if (m != null) {
      final hh = int.parse(m.group(1)!);
      final mm = int.parse(m.group(2)!);
      if (hh < 0 || hh > 23 || mm < 0 || mm > 59) return null;
      final now = DateTime.now();
      var dt = DateTime(now.year, now.month, now.day, hh, mm);
      if (dt.isBefore(now)) dt = dt.add(const Duration(days: 1));
      return dt;
    }

    return null;
  }
}

class _ParsedPayload {
  final String reminderId;
  final bool isAlarm;

  const _ParsedPayload({required this.reminderId, required this.isAlarm});
}

_ParsedPayload? _parsePayload(String? payload) {
  if (payload == null || payload.isEmpty) return null;
  if (payload.startsWith('alarm:')) {
    final id = payload.substring('alarm:'.length);
    return id.isEmpty ? null : _ParsedPayload(reminderId: id, isAlarm: true);
  }
  if (payload.startsWith('pre:')) {
    final id = payload.substring('pre:'.length);
    return id.isEmpty ? null : _ParsedPayload(reminderId: id, isAlarm: false);
  }
  if (payload.startsWith('notify:')) {
    final id = payload.substring('notify:'.length);
    return id.isEmpty ? null : _ParsedPayload(reminderId: id, isAlarm: false);
  }
  return _ParsedPayload(reminderId: payload, isAlarm: true);
}
