enum RepeatType { none, weekly, monthly }

RepeatType repeatTypeFromString(String? value) {
  switch (value) {
    case 'weekly':
      return RepeatType.weekly;
    case 'monthly':
      return RepeatType.monthly;
    default:
      return RepeatType.none;
  }
}

String? repeatTypeToString(RepeatType type) {
  switch (type) {
    case RepeatType.weekly:
      return 'weekly';
    case RepeatType.monthly:
      return 'monthly';
    case RepeatType.none:
      return null;
  }
}

List<int> parseRepeatDays(dynamic raw) {
  if (raw is Iterable) {
    final days = raw
        .map((e) => e is num ? e.toInt() : int.tryParse(e.toString()))
        .whereType<int>()
        .where((v) => v > 0)
        .toSet()
        .toList();
    days.sort();
    return days;
  }
  return const [];
}

int minutesOfDay(DateTime dt) => dt.hour * 60 + dt.minute;

DateTime dateWithMinutes(DateTime date, int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return DateTime(date.year, date.month, date.day, h, m);
}

DateTime? nextOccurrence({
  required DateTime from,
  required RepeatType type,
  required List<int> days,
  required int minutes,
}) {
  if (type == RepeatType.none) return from;
  if (days.isEmpty) return null;

  if (type == RepeatType.weekly) {
    final start = DateTime(from.year, from.month, from.day);
    for (var i = 0; i < 14; i += 1) {
      final date = start.add(Duration(days: i));
      if (!days.contains(date.weekday)) continue;
      final candidate = dateWithMinutes(date, minutes);
      if (!candidate.isBefore(from)) return candidate;
    }
    return null;
  }

  if (type == RepeatType.monthly) {
    final sorted = [...days]..sort();
    for (var offset = 0; offset < 24; offset += 1) {
      final monthStart = DateTime(from.year, from.month + offset, 1);
      final daysInMonth = DateTime(monthStart.year, monthStart.month + 1, 0).day;
      for (final day in sorted) {
        if (day > daysInMonth) continue;
        final candidate = DateTime(
          monthStart.year,
          monthStart.month,
          day,
          minutes ~/ 60,
          minutes % 60,
        );
        if (!candidate.isBefore(from)) return candidate;
      }
    }
  }

  return null;
}

List<DateTime> occurrencesInRange({
  required DateTime start,
  required DateTime end,
  required RepeatType type,
  required List<int> days,
  required int minutes,
}) {
  if (type == RepeatType.none || days.isEmpty) return const [];
  final results = <DateTime>[];

  if (type == RepeatType.weekly) {
    var cursor = DateTime(start.year, start.month, start.day);
    final endDay = DateTime(end.year, end.month, end.day);
    while (!cursor.isAfter(endDay)) {
      if (days.contains(cursor.weekday)) {
        final candidate = dateWithMinutes(cursor, minutes);
        if (!candidate.isBefore(start) && !candidate.isAfter(end)) {
          results.add(candidate);
        }
      }
      cursor = cursor.add(const Duration(days: 1));
    }
  } else if (type == RepeatType.monthly) {
    final sorted = [...days]..sort();
    var cursor = DateTime(start.year, start.month, 1);
    final endMonth = DateTime(end.year, end.month, 1);
    while (!cursor.isAfter(endMonth)) {
      final daysInMonth = DateTime(cursor.year, cursor.month + 1, 0).day;
      for (final day in sorted) {
        if (day > daysInMonth) continue;
        final candidate = DateTime(
          cursor.year,
          cursor.month,
          day,
          minutes ~/ 60,
          minutes % 60,
        );
        if (!candidate.isBefore(start) && !candidate.isAfter(end)) {
          results.add(candidate);
        }
      }
      cursor = DateTime(cursor.year, cursor.month + 1, 1);
    }
  }

  results.sort();
  return results;
}
