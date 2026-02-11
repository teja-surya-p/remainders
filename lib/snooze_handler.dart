import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'firebase_options.dart';
import 'alarm_screen.dart';
import 'notifs.dart';
import 'repeat_utils.dart';
import 'snooze_screen.dart';

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

    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final doc = FirebaseFirestore.instance
        .doc('users/${user.uid}/reminders/$reminderId');

    DateTime? newDueAt;

    if (action == Notifs.aSnooze5) {
      newDueAt = DateTime.now().add(const Duration(minutes: 5));
    } else if (action == Notifs.aSnooze10) {
      newDueAt = DateTime.now().add(const Duration(minutes: 10));
    } else if (action == Notifs.aSnooze30) {
      newDueAt = DateTime.now().add(const Duration(minutes: 30));
    } else if (action == Notifs.aCustom) {
      final input = (response.input ?? '').trim();
      if (input.isNotEmpty) {
        newDueAt = SnoozeParse.parseCustom(input);
      }

      if (newDueAt == null && openCustomUi) {
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
    } else if (action == Notifs.aDismiss) {
      Map<String, dynamic>? data;
      try {
        final snap = await doc.get();
        data = snap.data();
        final mainId = (data?['notifIdMain'] as num?)?.toInt();
        final preId = (data?['notifIdPre'] as num?)?.toInt();
        if (mainId != null) await Notifs.cancel(mainId);
        if (preId != null) await Notifs.cancel(preId);
      } catch (_) {}

      final repeatType = repeatTypeFromString(data?['repeatType'] as String?);
      final repeatDays = parseRepeatDays(data?['repeatDays']);
      final repeatTime = (data?['repeatTime'] as num?)?.toInt();
      final isRepeating =
          repeatType != RepeatType.none && repeatDays.isNotEmpty;
      final dueAt = (data?['dueAt'] as Timestamp?)?.toDate() ?? DateTime.now();

      if (isRepeating) {
        final minutes = repeatTime ?? minutesOfDay(dueAt);
        final next = nextOccurrence(
          from: DateTime.now().add(const Duration(seconds: 1)),
          type: repeatType,
          days: repeatDays,
          minutes: minutes,
        );
        if (next != null) {
          await doc.update({
            'dueAt': Timestamp.fromDate(next),
            'completed': false,
            'missed': false,
            'lastOccurrenceAt': Timestamp.fromDate(dueAt),
            'lastOccurrenceStatus': 'stopped',
            'updatedAt': FieldValue.serverTimestamp(),
            if (repeatTime == null) 'repeatTime': minutes,
          });
        }
      } else {
        await doc.update({
          'completed': true,
          'missed': false,
          'lastOccurrenceAt': Timestamp.fromDate(dueAt),
          'lastOccurrenceStatus': 'stopped',
          'updatedAt': FieldValue.serverTimestamp(),
          'dismissedAt': FieldValue.serverTimestamp(),
        });
      }
      return;
    } else {
      return;
    }

    if (newDueAt == null) return;

    await doc.update({
      'dueAt': Timestamp.fromDate(newDueAt),
      'completed': false,
      'missed': false,
      'updatedAt': FieldValue.serverTimestamp(),
      'lastSnoozedAt': FieldValue.serverTimestamp(),
      'lastSnoozedMinutes': _minutesFromNow(newDueAt),
      'lastSnoozedPlatform': Platform.isIOS ? 'ios' : 'android',
    });
  }

  static int _minutesFromNow(DateTime dt) {
    final diff = dt.difference(DateTime.now());
    final m = diff.inMinutes;
    return m < 0 ? 0 : m;
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
  return _ParsedPayload(reminderId: payload, isAlarm: true);
}
