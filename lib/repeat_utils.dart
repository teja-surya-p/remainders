import 'reminder_model.dart';

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

DateTime? nextOccurrence({
  required DateTime from,
  required RepeatType type,
  required List<int> days,
  required int minutes,
  int? intervalDays,
  List<int>? timesOfDay,
  DateTime? anchorDate,
  DateTime? endAt,
}) {
  final normalizedTimes = _normalizeTimes(timesOfDay, fallback: minutes);

  if (type == RepeatType.none) {
    final candidate = _firstTimeOnDate(from, normalizedTimes, notBefore: from);
    if (candidate == null) return null;
    if (!_withinEndDate(candidate, endAt)) return null;
    return candidate;
  }

  if (type == RepeatType.daily) {
    final startDate = DateTime(from.year, from.month, from.day);
    for (var i = 0; i < 3660; i += 1) {
      final date = startDate.add(Duration(days: i));
      final candidate = _firstTimeOnDate(
        date,
        normalizedTimes,
        notBefore: from,
      );
      if (candidate == null) continue;
      if (!_withinEndDate(candidate, endAt)) return null;
      return candidate;
    }
    return null;
  }

  if (type == RepeatType.weekly) {
    if (days.isEmpty) return null;
    final allowed = days.toSet();
    final startDate = DateTime(from.year, from.month, from.day);
    for (var i = 0; i < 3660; i += 1) {
      final date = startDate.add(Duration(days: i));
      if (!allowed.contains(date.weekday)) continue;
      final candidate = _firstTimeOnDate(
        date,
        normalizedTimes,
        notBefore: from,
      );
      if (candidate == null) continue;
      if (!_withinEndDate(candidate, endAt)) return null;
      return candidate;
    }
    return null;
  }

  if (type == RepeatType.interval) {
    final every = intervalDays ?? 1;
    if (every <= 0) return null;
    final base = DateTime(
      (anchorDate ?? from).year,
      (anchorDate ?? from).month,
      (anchorDate ?? from).day,
    );
    final startDate = DateTime(from.year, from.month, from.day);
    for (var i = 0; i < 3660; i += 1) {
      final date = startDate.add(Duration(days: i));
      final diff = date.difference(base).inDays;
      if (diff < 0 || diff % every != 0) continue;
      final candidate = _firstTimeOnDate(
        date,
        normalizedTimes,
        notBefore: from,
      );
      if (candidate == null) continue;
      if (!_withinEndDate(candidate, endAt)) return null;
      return candidate;
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
  int? intervalDays,
  List<int>? timesOfDay,
  DateTime? anchorDate,
  DateTime? endAt,
}) {
  if (end.isBefore(start)) return const [];

  final out = <DateTime>[];
  final normalizedTimes = _normalizeTimes(timesOfDay, fallback: minutes);
  final lastAllowed = endAt != null && endAt.isBefore(end) ? endAt : end;

  if (type == RepeatType.none) {
    final c = _firstTimeOnDate(start, normalizedTimes, notBefore: start);
    if (c != null && !c.isAfter(lastAllowed)) out.add(c);
    return out;
  }

  var cursor = DateTime(start.year, start.month, start.day);
  final lastDay = DateTime(
    lastAllowed.year,
    lastAllowed.month,
    lastAllowed.day,
  );
  final allowed = days.toSet();
  final base = DateTime(
    (anchorDate ?? start).year,
    (anchorDate ?? start).month,
    (anchorDate ?? start).day,
  );

  while (!cursor.isAfter(lastDay)) {
    var include = false;
    if (type == RepeatType.daily) {
      include = true;
    } else if (type == RepeatType.weekly) {
      include = allowed.contains(cursor.weekday);
    } else if (type == RepeatType.interval) {
      final every = intervalDays ?? 1;
      if (every > 0) {
        final diff = cursor.difference(base).inDays;
        include = diff >= 0 && diff % every == 0;
      }
    }

    if (include) {
      for (final time in normalizedTimes) {
        final candidate = dateWithMinutes(cursor, time);
        if (candidate.isBefore(start) || candidate.isAfter(lastAllowed)) {
          continue;
        }
        out.add(candidate);
      }
    }

    cursor = cursor.add(const Duration(days: 1));
  }

  out.sort();
  return out;
}

DateTime? _firstTimeOnDate(
  DateTime date,
  List<int> times, {
  required DateTime notBefore,
}) {
  for (final time in times) {
    final candidate = dateWithMinutes(date, time);
    if (!candidate.isBefore(notBefore)) return candidate;
  }
  return null;
}

bool _withinEndDate(DateTime value, DateTime? endAt) {
  if (endAt == null) return true;
  return !value.isAfter(endAt);
}

List<int> _normalizeTimes(List<int>? times, {required int fallback}) {
  final source = times == null || times.isEmpty ? [fallback] : times;
  final out = source.where((m) => m >= 0 && m <= 1439).toSet().toList();
  out.sort();
  if (out.isEmpty) return [fallback.clamp(0, 1439)];
  return out;
}
