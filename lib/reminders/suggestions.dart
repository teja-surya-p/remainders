import '../reminder_model.dart';

/// A better time to suggest for [reminder], judged from how it has been
/// answered: after 3 or more snoozes in a row, 15 minutes later; otherwise,
/// if it is usually completed at a consistent time at least 30 minutes away
/// from its schedule, that time. Null when there's nothing to suggest.
({int minuteOfDay, String message})? suggestTime(
  ReminderModel reminder,
  List<ReminderEvent> events, {
  required DateTime now,
}) {
  final scheduledMinute = reminder.recurrence.timesOfDay.isNotEmpty
      ? reminder.recurrence.timesOfDay.first
      : minutesOfDay(reminder.dueAt);

  if (reminder.consecutiveSnoozes >= 3) {
    final suggested = (scheduledMinute + 15) % 1440;
    return (
      minuteOfDay: suggested,
      message:
          'You snoozed this 3+ times. Would you like to move it to '
          '${_formatMinute(suggested)}?',
    );
  }

  final from = now.subtract(const Duration(days: 28));
  final completionMinutes = [
    for (final e in events)
      if (e.reminderId == reminder.id &&
          e.type == ReminderEventType.completed &&
          !e.occurredAt.isBefore(from))
        minutesOfDay(e.occurredAt),
  ]..sort();
  if (completionMinutes.length < 5) return null;

  final medianMinute = completionMinutes[completionMinutes.length ~/ 2];
  final closeCount = completionMinutes
      .where((m) => (m - medianMinute).abs() <= 30)
      .length;
  final consistency = closeCount / completionMinutes.length;
  if ((medianMinute - scheduledMinute).abs() < 30 || consistency < 0.7) {
    return null;
  }
  return (
    minuteOfDay: medianMinute,
    message:
        'You typically complete this at ${_formatMinute(medianMinute)}. '
        'Would you like to update the schedule?',
  );
}

String _formatMinute(int minute) {
  final h = (minute ~/ 60) % 24;
  final m = minute % 60;
  final suffix = h >= 12 ? 'PM' : 'AM';
  final hour12 = h % 12 == 0 ? 12 : h % 12;
  final mm = m.toString().padLeft(2, '0');
  return '$hour12:$mm $suffix';
}
