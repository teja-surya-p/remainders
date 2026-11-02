/// Pure scheduling logic: given a reminder and the current time, decide which
/// native alerts should be pending. No plugins, no I/O — fully unit-tested.
library;

import '../reminder_model.dart';
import '../repeat_utils.dart';
import 'alert_payload.dart';

class PlannerConfig {
  /// How long an alarm keeps ringing before it stops and counts as missed.
  final Duration ringWindow;

  /// How long after its time a plain (notify-only) reminder may still be
  /// delivered late, e.g. right after a reboot. Plain notifications can be
  /// swiped away without a trace, so this is short to avoid re-posting one
  /// the user already saw.
  final Duration notifyCatchUp;

  /// How many occurrences per repeating reminder to keep scheduled ahead, so
  /// repeats keep firing even if the app is never opened.
  final int maxOccurrences;

  /// Do not schedule occurrences further out than this.
  final Duration horizon;

  /// Delay used when an alert has to fire "now".
  final Duration catchUpDelay;

  const PlannerConfig({
    this.ringWindow = const Duration(minutes: 10),
    this.notifyCatchUp = const Duration(minutes: 1),
    this.maxOccurrences = 4,
    this.horizon = const Duration(days: 14),
    this.catchUpDelay = const Duration(seconds: 2),
  });
}

/// One native alert the scheduler should have pending.
class PlannedAlert {
  final int id;
  final AlertKind kind;
  final ReminderModel reminder;
  final DateTime occurrence;
  final DateTime fireAt;
  final String title;
  final String? body;

  const PlannedAlert({
    required this.id,
    required this.kind,
    required this.reminder,
    required this.occurrence,
    required this.fireAt,
    required this.title,
    required this.body,
  });

  String get payload => AlertPayload(
    kind: kind,
    reminderId: reminder.id,
    occurrence: occurrence,
  ).encode();

  /// Changes whenever anything visible about the alert changes, so the
  /// scheduler can skip re-posting identical alerts.
  String get signature => [
    id,
    epochMinute(fireAt),
    title,
    body ?? '',
    reminder.alertMode.name,
    reminder.priority.name,
    reminder.alarmSoundId,
    reminder.notificationSoundId,
  ].join('|');
}

class ReminderPlan {
  final List<PlannedAlert> alerts;

  /// The current occurrence's ring window has passed without an answer: the
  /// service should record a miss and advance a repeating reminder.
  final bool needsMissedOrAdvance;

  const ReminderPlan({required this.alerts, this.needsMissedOrAdvance = false});

  static const empty = ReminderPlan(alerts: []);
}

ReminderPlan planReminder(
  ReminderModel reminder,
  DateTime now, {
  PlannerConfig config = const PlannerConfig(),
}) {
  if (!reminder.isActive) return ReminderPlan.empty;

  final mainKind = reminder.alertMode == ReminderAlertMode.notifyOnly
      ? AlertKind.notify
      : AlertKind.alarm;
  final catchUp = mainKind == AlertKind.alarm
      ? config.ringWindow
      : config.notifyCatchUp;

  // An occurrence whose window has passed is the service's job to resolve;
  // the scheduler resolves it, then plans the reminder again in the same
  // sync.
  if (reminder.dueAt.isBefore(now.subtract(config.ringWindow))) {
    return const ReminderPlan(alerts: [], needsMissedOrAdvance: true);
  }

  final alerts = <PlannedAlert>[];
  final horizonEnd = now.add(config.horizon);
  final remindBefore = reminder.remindBeforeMinutes;

  var occurrence = reminder.dueAt;
  for (var i = 0; i < config.maxOccurrences; i += 1) {
    if (i > 0 && occurrence.isAfter(horizonEnd)) break;

    final isCurrent = i == 0;
    final title = isCurrent ? _titleWithSnoozes(reminder) : reminder.title;
    final body = isCurrent ? _bodyWithSnoozes(reminder) : _cleanBody(reminder);

    DateTime? fireAt;
    if (!occurrence.isBefore(now)) {
      fireAt = occurrence;
    } else if (now.difference(occurrence) <= catchUp) {
      // Due a moment ago and not yet answered: deliver it now. The scheduler
      // skips this if the alert is already on screen.
      fireAt = now.add(config.catchUpDelay);
    }
    if (fireAt != null) {
      alerts.add(
        PlannedAlert(
          id: stableNotificationId(reminder.id, occurrence, mainKind),
          kind: mainKind,
          reminder: reminder,
          occurrence: occurrence,
          fireAt: fireAt,
          title: title,
          body: body,
        ),
      );
    }

    if (remindBefore != null && remindBefore > 0) {
      final preAt = occurrence.subtract(Duration(minutes: remindBefore));
      if (preAt.isAfter(now)) {
        alerts.add(
          PlannedAlert(
            id: stableNotificationId(reminder.id, occurrence, AlertKind.pre),
            kind: AlertKind.pre,
            reminder: reminder,
            occurrence: occurrence,
            fireAt: preAt,
            title: mainKind == AlertKind.alarm
                ? 'Upcoming alarm'
                : 'Upcoming reminder',
            body: '${reminder.title} in $remindBefore minutes',
          ),
        );
      }
    }

    if (!reminder.recurrence.isRepeating) break;
    final next = _nextAfter(reminder.recurrence, occurrence);
    if (next == null) break;
    occurrence = next;
  }

  return ReminderPlan(alerts: alerts);
}

/// Next occurrence strictly after [previous], using the same rule the
/// reminder service applies when an occurrence is completed or missed, so
/// alerts scheduled ahead match where the reminder will actually move.
DateTime? _nextAfter(ReminderRecurrence recurrence, DateTime previous) {
  final minutes = recurrence.timesOfDay.isNotEmpty
      ? recurrence.timesOfDay.first
      : previous.hour * 60 + previous.minute;
  return nextOccurrence(
    from: previous.add(const Duration(minutes: 1)),
    type: recurrence.type,
    days: recurrence.weekdays,
    minutes: minutes,
    intervalDays: recurrence.intervalDays,
    timesOfDay: recurrence.timesOfDay,
    anchorDate: previous,
    endAt: recurrence.endAt,
  );
}

String? _cleanBody(ReminderModel reminder) {
  final cleaned = reminder.description?.trim();
  return cleaned == null || cleaned.isEmpty ? null : cleaned;
}

String _titleWithSnoozes(ReminderModel reminder) {
  if (reminder.consecutiveSnoozes < 1) return reminder.title;
  return '${reminder.title} (${reminder.consecutiveSnoozes}x snoozed)';
}

String? _bodyWithSnoozes(ReminderModel reminder) {
  final cleaned = _cleanBody(reminder);
  if (reminder.consecutiveSnoozes < 1) return cleaned;
  final suffix = 'Snoozed ${reminder.consecutiveSnoozes} times';
  return cleaned == null ? suffix : '$cleaned • $suffix';
}
