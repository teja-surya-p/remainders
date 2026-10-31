/// Identity of one scheduled alert: which reminder, which occurrence, which
/// kind. Encoded into the notification payload so any isolate (including the
/// background action handler) knows exactly what fired, and hashed into a
/// stable notification ID so re-planning the same occurrence is idempotent.
library;

enum AlertKind {
  /// Alarm-style alert (rings on the alarm volume, full screen).
  alarm,

  /// Plain notification for notify-only reminders.
  notify,

  /// Optional heads-up shown before the main alert.
  pre,
}

class AlertPayload {
  final AlertKind kind;
  final String reminderId;

  /// The occurrence this alert belongs to, at minute precision. Null only for
  /// payloads written by app versions before stable payloads existed.
  final DateTime? occurrence;

  const AlertPayload({
    required this.kind,
    required this.reminderId,
    this.occurrence,
  });

  bool get isAlarm => kind == AlertKind.alarm;

  /// `<kind>:<reminderId>@<epoch minute, UTC>`, e.g. `alarm:r_1_2@29340000`.
  String encode() {
    final occ = occurrence;
    if (occ == null) return '${kind.name}:$reminderId';
    return '${kind.name}:$reminderId@${epochMinute(occ)}';
  }

  /// Parses current and legacy payloads (`alarm:<id>`, `pre:<id>`,
  /// `notify:<id>`, or a bare id treated as an alarm). Returns null for
  /// payloads that do not belong to a reminder.
  static AlertPayload? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    var kind = AlertKind.alarm;
    var rest = raw;
    final colon = raw.indexOf(':');
    if (colon > 0) {
      final name = raw.substring(0, colon);
      final match = AlertKind.values.where((k) => k.name == name);
      if (match.isEmpty) return null;
      kind = match.first;
      rest = raw.substring(colon + 1);
    }
    DateTime? occurrence;
    final at = rest.lastIndexOf('@');
    if (at >= 0) {
      final minute = int.tryParse(rest.substring(at + 1));
      if (minute == null) return null;
      occurrence = DateTime.fromMillisecondsSinceEpoch(
        minute * Duration.millisecondsPerMinute,
        isUtc: true,
      ).toLocal();
      rest = rest.substring(0, at);
    }
    if (rest.isEmpty) return null;
    return AlertPayload(kind: kind, reminderId: rest, occurrence: occurrence);
  }
}

/// Minutes since the Unix epoch (UTC) — the precision reminders use.
int epochMinute(DateTime t) =>
    t.toUtc().millisecondsSinceEpoch ~/ Duration.millisecondsPerMinute;

/// True when [a] and [b] fall in the same minute.
bool sameMinute(DateTime a, DateTime b) => epochMinute(a) == epochMinute(b);

/// Stable, positive 31-bit notification ID for one alert.
///
/// FNV-1a over `reminderId|epochMinute|kind`. The same occurrence always maps
/// to the same ID, so scheduling it again replaces instead of duplicating.
int stableNotificationId(
  String reminderId,
  DateTime occurrence,
  AlertKind kind,
) {
  var hash = 0x811c9dc5;
  final key = '$reminderId|${epochMinute(occurrence)}|${kind.name}';
  for (final unit in key.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  final id = hash & 0x7fffffff;
  return id == 0 ? 1 : id;
}
