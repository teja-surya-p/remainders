import 'package:flutter_test/flutter_test.dart';
import 'package:snooze_app/reminder_model.dart';
import 'package:snooze_app/scheduling/alert_payload.dart';
import 'package:snooze_app/scheduling/schedule_planner.dart';

ReminderModel reminder({
  String id = 'r_1_2',
  required DateTime dueAt,
  ReminderRecurrence? recurrence,
  ReminderAlertMode alertMode = ReminderAlertMode.ringAndNotify,
  bool completed = false,
  bool missed = false,
  int? remindBeforeMinutes,
  int consecutiveSnoozes = 0,
  String? description,
}) {
  final created = DateTime(2026, 6, 1);
  return ReminderModel(
    id: id,
    title: 'Take medicine',
    description: description,
    dueAt: dueAt,
    createdAt: created,
    updatedAt: created,
    recurrence: recurrence,
    alertMode: alertMode,
    completed: completed,
    missed: missed,
    remindBeforeMinutes: remindBeforeMinutes,
    consecutiveSnoozes: consecutiveSnoozes,
  );
}

ReminderRecurrence daily(int minutesOfDay) =>
    ReminderRecurrence(type: RepeatType.daily, timesOfDay: [minutesOfDay]);

void main() {
  group('AlertPayload', () {
    test('round-trips kind, reminder id and occurrence minute', () {
      final occ = DateTime(2026, 6, 10, 9);
      final encoded = AlertPayload(
        kind: AlertKind.alarm,
        reminderId: 'r_1_2',
        occurrence: occ,
      ).encode();
      final decoded = AlertPayload.decode(encoded)!;
      expect(decoded.kind, AlertKind.alarm);
      expect(decoded.reminderId, 'r_1_2');
      expect(decoded.occurrence, occ);
    });

    test('reads payloads from older app versions', () {
      expect(AlertPayload.decode('alarm:r_9')!.isAlarm, isTrue);
      expect(AlertPayload.decode('pre:r_9')!.kind, AlertKind.pre);
      expect(AlertPayload.decode('notify:r_9')!.kind, AlertKind.notify);
      final bare = AlertPayload.decode('r_9')!;
      expect(bare.reminderId, 'r_9');
      expect(bare.isAlarm, isTrue);
      expect(bare.occurrence, isNull);
    });

    test('rejects empty and foreign payloads', () {
      for (final bad in [null, '', 'weird:r_1', 'alarm:', 'alarm:r_1@x']) {
        expect(AlertPayload.decode(bad), isNull, reason: '$bad');
      }
    });
  });

  group('stableNotificationId', () {
    final occ = DateTime(2026, 6, 10, 9);
    test('is deterministic and positive', () {
      final a = stableNotificationId('r_1', occ, AlertKind.alarm);
      expect(a, stableNotificationId('r_1', occ, AlertKind.alarm));
      expect(a, greaterThan(0));
      expect(a, lessThanOrEqualTo(0x7fffffff));
    });

    test('differs by reminder, occurrence and kind', () {
      final ids = {
        stableNotificationId('r_1', occ, AlertKind.alarm),
        stableNotificationId('r_2', occ, AlertKind.alarm),
        stableNotificationId(
          'r_1',
          occ.add(const Duration(days: 1)),
          AlertKind.alarm,
        ),
        stableNotificationId('r_1', occ, AlertKind.pre),
        stableNotificationId('r_1', occ, AlertKind.notify),
      };
      expect(ids, hasLength(5));
    });
  });

  group('planReminder', () {
    final now = DateTime(2026, 6, 10, 8);

    test('completed or missed reminders schedule nothing', () {
      for (final r in [
        reminder(dueAt: DateTime(2026, 6, 10, 9), completed: true),
        reminder(dueAt: DateTime(2026, 6, 10, 9), missed: true),
      ]) {
        final plan = planReminder(r, now);
        expect(plan.alerts, isEmpty);
        expect(plan.needsMissedOrAdvance, isFalse);
      }
    });

    test('a future one-off alarm schedules exactly one alarm at its time', () {
      final due = DateTime(2026, 6, 10, 9);
      final plan = planReminder(reminder(dueAt: due), now);
      expect(plan.alerts, hasLength(1));
      final a = plan.alerts.single;
      expect(a.kind, AlertKind.alarm);
      expect(a.fireAt, due);
      expect(a.id, stableNotificationId('r_1_2', due, AlertKind.alarm));
      expect(AlertPayload.decode(a.payload)!.occurrence, due);
    });

    test('notify-only reminders schedule a plain notification', () {
      final plan = planReminder(
        reminder(
          dueAt: DateTime(2026, 6, 10, 9),
          alertMode: ReminderAlertMode.notifyOnly,
        ),
        now,
      );
      expect(plan.alerts.single.kind, AlertKind.notify);
    });

    test('an alarm due a few minutes ago (never answered) rings now', () {
      final due = DateTime(2026, 6, 10, 7, 55);
      final plan = planReminder(reminder(dueAt: due), now);
      expect(plan.alerts.single.fireAt, now.add(const Duration(seconds: 2)));
      expect(plan.alerts.single.occurrence, due);
    });

    test('a plain notification overdue by minutes is not re-posted', () {
      final plan = planReminder(
        reminder(
          dueAt: DateTime(2026, 6, 10, 7, 55),
          alertMode: ReminderAlertMode.notifyOnly,
        ),
        now,
      );
      expect(plan.alerts, isEmpty);
      expect(plan.needsMissedOrAdvance, isFalse);
    });

    test('past the 10-minute ring window it asks for missed/advance', () {
      final plan = planReminder(
        reminder(dueAt: DateTime(2026, 6, 10, 7, 49)),
        now,
      );
      expect(plan.alerts, isEmpty);
      expect(plan.needsMissedOrAdvance, isTrue);
    });

    test('a daily reminder keeps the next 4 occurrences scheduled', () {
      final plan = planReminder(
        reminder(dueAt: DateTime(2026, 6, 10, 9), recurrence: daily(9 * 60)),
        now,
      );
      expect(plan.alerts.map((a) => a.fireAt), [
        DateTime(2026, 6, 10, 9),
        DateTime(2026, 6, 11, 9),
        DateTime(2026, 6, 12, 9),
        DateTime(2026, 6, 13, 9),
      ]);
      expect(plan.alerts.map((a) => a.id).toSet(), hasLength(4));
    });

    test('schedule-ahead stays on 09:00 across the autumn DST change', () {
      final plan = planReminder(
        reminder(dueAt: DateTime(2026, 10, 31, 9), recurrence: daily(9 * 60)),
        DateTime(2026, 10, 31, 8),
      );
      expect(plan.alerts.map((a) => a.fireAt), [
        DateTime(2026, 10, 31, 9),
        DateTime(2026, 11, 1, 9),
        DateTime(2026, 11, 2, 9),
        DateTime(2026, 11, 3, 9),
      ]);
    });

    test('weekly repeats stop at the 14-day horizon (measured from now)', () {
      final plan = planReminder(
        reminder(
          dueAt: DateTime(2026, 6, 10, 9),
          recurrence: ReminderRecurrence(
            type: RepeatType.weekly,
            weekdays: const [DateTime.wednesday],
            timesOfDay: const [9 * 60],
          ),
        ),
        now,
      );
      expect(plan.alerts.map((a) => a.fireAt), [
        DateTime(2026, 6, 10, 9),
        DateTime(2026, 6, 17, 9),
        // June 24 09:00 is 14 days + 1 hour after `now` (June 10 08:00).
      ]);
    });

    test('an end date stops scheduling ahead', () {
      final plan = planReminder(
        reminder(
          dueAt: DateTime(2026, 6, 10, 9),
          recurrence: ReminderRecurrence(
            type: RepeatType.daily,
            timesOfDay: const [9 * 60],
            endAt: DateTime(2026, 6, 11, 23, 59),
          ),
        ),
        now,
      );
      expect(plan.alerts, hasLength(2));
    });

    test('remind-before adds a heads-up before each future occurrence', () {
      final plan = planReminder(
        reminder(
          dueAt: DateTime(2026, 6, 10, 9),
          recurrence: daily(9 * 60),
          remindBeforeMinutes: 10,
        ),
        now,
      );
      final pre = plan.alerts.where((a) => a.kind == AlertKind.pre).toList();
      expect(pre.map((a) => a.fireAt).first, DateTime(2026, 6, 10, 8, 50));
      expect(pre, hasLength(4));
    });

    test('no heads-up by default', () {
      final plan = planReminder(reminder(dueAt: DateTime(2026, 6, 10, 9)), now);
      expect(plan.alerts.where((a) => a.kind == AlertKind.pre), isEmpty);
    });

    test('snooze count shows only on the current occurrence', () {
      final plan = planReminder(
        reminder(
          dueAt: DateTime(2026, 6, 10, 9, 10),
          recurrence: daily(9 * 60),
          consecutiveSnoozes: 2,
        ),
        now,
      );
      expect(plan.alerts.first.title, 'Take medicine (2x snoozed)');
      expect(plan.alerts[1].title, 'Take medicine');
      expect(plan.alerts[1].fireAt, DateTime(2026, 6, 11, 9));
    });

    test('re-planning after an occurrence keeps the same IDs ahead', () {
      final r = reminder(
        dueAt: DateTime(2026, 6, 10, 9),
        recurrence: daily(9 * 60),
      );
      final before = planReminder(
        r,
        now,
      ).alerts.skip(1).map((a) => a.id).toList();
      // The service advances dueAt to the next day once today is done.
      final advanced = r.copyWith(dueAt: DateTime(2026, 6, 11, 9));
      final after = planReminder(advanced, DateTime(2026, 6, 10, 9, 5)).alerts;
      expect(after.take(3).map((a) => a.id).toList(), before);
    });
  });
}
