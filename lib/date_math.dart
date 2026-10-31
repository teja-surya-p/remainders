/// Calendar-day arithmetic for local wall-clock times.
///
/// `date.add(Duration(days: n))` adds n × 24 hours. Across a daylight-saving
/// change that lands an hour off — on the previous calendar day after the
/// autumn change — so recurring reminders drift or repeat a day. These helpers
/// move by calendar days and keep the wall-clock time instead.
library;

/// [date] moved by [days] calendar days, keeping its wall-clock time.
///
/// UTC values stay UTC. A local time that does not exist on the target day
/// (inside a spring-forward gap) is normalised by [DateTime] to the next
/// valid time.
DateTime addDays(DateTime date, int days) {
  if (date.isUtc) {
    return DateTime.utc(
      date.year,
      date.month,
      date.day + days,
      date.hour,
      date.minute,
      date.second,
      date.millisecond,
      date.microsecond,
    );
  }
  return DateTime(
    date.year,
    date.month,
    date.day + days,
    date.hour,
    date.minute,
    date.second,
    date.millisecond,
    date.microsecond,
  );
}

/// Whole calendar days from [from] to [to] (negative when [to] is earlier),
/// ignoring the time of day and any daylight-saving hour shift.
int daysBetween(DateTime from, DateTime to) {
  final a = DateTime.utc(from.year, from.month, from.day);
  final b = DateTime.utc(to.year, to.month, to.day);
  return b.difference(a).inDays;
}
