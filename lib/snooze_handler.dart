import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'alarm_ui.dart';
import 'app_services.dart';
import 'date_math.dart';
import 'firebase_options.dart';
import 'notifs.dart';
import 'pages/snooze_screen.dart';
import 'reminder_scheduler.dart';
import 'scheduling/alert_payload.dart';

/// Entry point for notification actions while the app is in the background
/// or closed. Runs in its own isolate, which has none of the app's state.
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

    final payload = AlertPayload.decode(response.payload);
    if (payload == null) return;

    // A background isolate starts with no time zone; scheduling the snoozed
    // alarm would otherwise throw and the alarm would be lost.
    await Notifs.ensureTimeZone();

    // Firebase and AppServices are per isolate, so the background isolate
    // initializes them itself before reading or writing reminders.
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } on FirebaseException catch (e) {
      // The app's own isolate may already have initialized it.
      if (e.code != 'duplicate-app') rethrow;
    }
    await AppServices.initialize();

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await AppServices.bindUser(user);
    ReminderScheduler.configure(AppServices.reminders);

    final action = response.actionId ?? '';
    final now = DateTime.now();

    if (action.isEmpty) {
      // Plain tap on the notification (or a full-screen launch).
      if (openCustomUi && payload.isAlarm) {
        unawaited(
          AlarmUi.show(
            reminderId: payload.reminderId,
            occurrence: payload.occurrence,
          ),
        );
      }
      return;
    }

    switch (action) {
      case Notifs.aSnooze5:
        await _snooze(payload, now.add(const Duration(minutes: 5)));
      case Notifs.aSnooze10:
        await _snooze(payload, now.add(const Duration(minutes: 10)));
      case Notifs.aSnooze30:
        await _snooze(payload, now.add(const Duration(minutes: 30)));
      case Notifs.aCustom:
        final custom = SnoozeParse.parseCustom((response.input ?? '').trim());
        if (custom != null) {
          await _snooze(payload, custom);
        } else if (openCustomUi) {
          // No usable inline input: let the app collect the time.
          final nav = Notifs.navKey.currentState;
          if (nav != null) {
            unawaited(
              nav.push(
                MaterialPageRoute<void>(
                  builder: (_) => SnoozeScreen(reminderId: payload.reminderId),
                ),
              ),
            );
          }
        }
      case Notifs.aDismiss:
        await AppServices.reminders.dismissReminder(
          payload.reminderId,
          expectedDueAt: payload.occurrence,
        );
        await _replan(payload.reminderId);
    }
  }

  static Future<void> _snooze(AlertPayload payload, DateTime until) async {
    await AppServices.reminders.snoozeReminder(
      payload.reminderId,
      until,
      expectedDueAt: payload.occurrence,
    );
    await _replan(payload.reminderId);
  }

  /// The background isolate has no live data stream, so it re-plans the
  /// reminder itself before exiting; otherwise a snoozed alarm would never be
  /// scheduled again.
  static Future<void> _replan(String reminderId) async {
    final updated = await AppServices.reminders.getReminder(reminderId);
    if (updated == null) {
      await ReminderScheduler.cancelReminder(reminderId);
    } else {
      await ReminderScheduler.replanOne(updated);
    }
  }
}

class SnoozeParse {
  /// Parses a custom snooze: a number of minutes ("15") or a clock time
  /// ("09:30", the next time the clock shows it).
  /// [now] is injectable for tests; production callers use the clock.
  static DateTime? parseCustom(String input, {DateTime? now}) {
    final s = input.trim();
    if (s.isEmpty) return null;

    final clock = now ?? DateTime.now();
    final mins = int.tryParse(s);
    if (mins != null && mins > 0) {
      return clock.add(Duration(minutes: mins));
    }

    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(s);
    if (m != null) {
      final hh = int.parse(m.group(1)!);
      final mm = int.parse(m.group(2)!);
      if (hh < 0 || hh > 23 || mm < 0 || mm > 59) return null;
      var dt = DateTime(clock.year, clock.month, clock.day, hh, mm);
      if (dt.isBefore(clock)) dt = addDays(dt, 1);
      return dt;
    }

    return null;
  }
}
