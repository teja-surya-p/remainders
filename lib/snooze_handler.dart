import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'app_services.dart';
import 'firebase_options.dart';
import 'notifs.dart';
import 'pages/alarm_screen.dart';
import 'pages/snooze_screen.dart';
import 'reminder_scheduler.dart';

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

    // Firebase / AppServices statics are per-isolate, so the notification
    // background isolate must initialize them itself before any Firestore
    // write or read can succeed.
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } on FirebaseException catch (e) {
      // The foreground isolate may have already initialized the default app
      // when this callback runs in the same process; treat that as success.
      if (e.code != 'duplicate-app') rethrow;
    }

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
          unawaited(
            nav.push(
              MaterialPageRoute<void>(
                builder: (_) => AlarmScreen(reminderId: reminderId),
              ),
            ),
          );
        }
      }
      return;
    }

    if (action == Notifs.aSnooze5) {
      await _snoozeAndReschedule(
        reminderId,
        DateTime.now().add(const Duration(minutes: 5)),
      );
      return;
    }

    if (action == Notifs.aSnooze10) {
      await _snoozeAndReschedule(
        reminderId,
        DateTime.now().add(const Duration(minutes: 10)),
      );
      return;
    }

    if (action == Notifs.aSnooze30) {
      await _snoozeAndReschedule(
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
          await _snoozeAndReschedule(reminderId, custom);
          return;
        }
      }

      // Fall back to the in-app picker when there's no inline input.
      // In the background isolate (`openCustomUi: false`) we have no
      // navigator and no way to collect a duration, so we leave the original
      // notification in place for the foreground app to handle once
      // launched.
      if (openCustomUi) {
        final nav = Notifs.navKey.currentState;
        if (nav != null) {
          unawaited(
            nav.push(
              MaterialPageRoute<void>(
                builder: (_) => SnoozeScreen(reminderId: reminderId),
              ),
            ),
          );
        }
      }
      return;
    }

    if (action == Notifs.aDismiss) {
      await _dismissAndCancel(reminderId);
      return;
    }
  }

  /// Snoozes and immediately re-schedules the next notification, even from
  /// the notification background isolate.
  ///
  /// `ReminderService.snoozeReminder` only writes to Firestore + clears the
  /// notification IDs; it relies on `ReminderScheduler` (a stream listener
  /// started in the foreground `_AuthGate`) to actually re-arm the native
  /// notification. The background isolate has no such listener, so we
  /// schedule the next notification directly here before the isolate exits.
  static Future<void> _snoozeAndReschedule(
    String reminderId,
    DateTime newDueAt,
  ) async {
    await AppServices.reminders.snoozeReminder(reminderId, newDueAt);
    final updated = await AppServices.reminders.getReminder(reminderId);
    if (updated == null) return;
    ReminderScheduler.configure(AppServices.reminders);
    await ReminderScheduler.scheduleOne(AppServices.reminders, updated);
  }

  /// Marks the reminder complete and proactively cancels any native
  /// notifications still in flight, so a killed-app dismiss does not leave
  /// the alarm scheduled to ring again on its original time.
  static Future<void> _dismissAndCancel(String reminderId) async {
    final before = await AppServices.reminders.getReminder(reminderId);
    await AppServices.reminders.dismissReminder(reminderId);
    if (before != null) {
      await ReminderScheduler.cancelAllFor(before);
    }
    final after = await AppServices.reminders.getReminder(reminderId);
    if (after != null) {
      // Recurring reminders advance to the next occurrence on dismiss; make
      // sure that next occurrence is actually scheduled from the BG isolate.
      ReminderScheduler.configure(AppServices.reminders);
      await ReminderScheduler.scheduleOne(AppServices.reminders, after);
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
