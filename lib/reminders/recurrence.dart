import '../date_math.dart';
import '../reminder_model.dart';
import '../repeat_utils.dart';

/// The first due time for a new or edited reminder: [dueAt] itself for a
/// one-off; for a repeat, its first occurrence not before [reference].
DateTime? resolveInitialDue(
  DateTime dueAt,
  ReminderRecurrence recurrence, {
  required DateTime reference,
}) {
  if (!recurrence.isRepeating) {
    return dueAt;
  }

  final minutes = recurrence.timesOfDay.isNotEmpty
      ? recurrence.timesOfDay.first
      : minutesOfDay(dueAt);

  final from = dueAt.isAfter(reference) ? dueAt : reference;

  return nextOccurrence(
    from: from,
    type: recurrence.type,
    days: recurrence.weekdays,
    minutes: minutes,
    intervalDays: recurrence.intervalDays,
    timesOfDay: recurrence.timesOfDay,
    anchorDate: dueAt,
    endAt: recurrence.endAt,
  );
}

/// When a repeating reminder is due next, at or after [from]. The one rule
/// used both when an occurrence is answered or missed (ReminderService) and
/// when alarms are scheduled ahead (the planner), so the two always agree.
/// Null for a one-off reminder or a repeat that has ended.
DateTime? nextRecurringDue({
  required DateTime from,
  required ReminderRecurrence recurrence,
  required DateTime anchor,
}) {
  if (!recurrence.isRepeating) return null;

  final minutes = recurrence.timesOfDay.isNotEmpty
      ? recurrence.timesOfDay.first
      : minutesOfDay(anchor);

  return nextOccurrence(
    from: from,
    type: recurrence.type,
    days: recurrence.weekdays,
    minutes: minutes,
    intervalDays: recurrence.intervalDays,
    timesOfDay: recurrence.timesOfDay,
    anchorDate: anchor,
    endAt: recurrence.endAt,
  );
}

/// Whether [scheduledAt] directly follows the reminder's last occurrence and
/// that one was completed, i.e. completing now extends the streak.
bool isConsecutiveScheduledOccurrence(
  ReminderModel reminder,
  DateTime scheduledAt,
) {
  if (reminder.lastOccurrenceStatus != 'completed') return false;
  final prev = reminder.lastOccurrenceAt;
  if (prev == null) return false;

  if (!reminder.recurrence.isRepeating) {
    return dayOnly(prev) == dayOnly(addDays(scheduledAt, -1));
  }

  final expected = nextRecurringDue(
    from: prev.add(const Duration(seconds: 1)),
    recurrence: reminder.recurrence,
    anchor: prev,
  );
  if (expected == null) return false;

  final diff = expected.difference(scheduledAt).inMinutes.abs();
  return diff <= 1;
}
