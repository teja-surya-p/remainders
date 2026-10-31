import 'package:flutter_test/flutter_test.dart';
import 'package:snooze_app/date_math.dart';
import 'package:snooze_app/reminder_model.dart';
import 'package:snooze_app/repeat_utils.dart';

// Reminders keep local wall-clock times, so they must land on the right
// calendar day and hour across daylight-saving changes. These expectations
// hold in every time zone; they only *fail* under a DST zone when the code
// adds 24-hour durations instead of calendar days. tool/check.sh runs the
// suite again with TZ=America/New_York (DST ends 2026-11-01, starts
// 2026-03-08) so the bug cannot come back unnoticed.
void main() {
  const nineAm = 9 * 60;

  group('across the November fall-back day', () {
    test('every-2-days repeat keeps its rhythm after the change', () {
      // Anchored Oct 30 → Oct 30, Nov 1, Nov 3, …
      final next = nextOccurrence(
        from: DateTime(2026, 11, 1, 9, 1),
        type: RepeatType.interval,
        days: const [],
        minutes: nineAm,
        intervalDays: 2,
        anchorDate: DateTime(2026, 10, 30),
      );
      expect(next, DateTime(2026, 11, 3, 9));
    });

    test('interval occurrences in a range land on the right days', () {
      final out = occurrencesInRange(
        start: DateTime(2026, 10, 30),
        end: DateTime(2026, 11, 8, 23, 59),
        type: RepeatType.interval,
        days: const [],
        minutes: nineAm,
        intervalDays: 2,
        anchorDate: DateTime(2026, 10, 30),
      );
      expect(out, [
        DateTime(2026, 10, 30, 9),
        DateTime(2026, 11, 1, 9),
        DateTime(2026, 11, 3, 9),
        DateTime(2026, 11, 5, 9),
        DateTime(2026, 11, 7, 9),
      ]);
    });

    test('daily occurrences: one per day, no duplicate on the long day', () {
      final out = occurrencesInRange(
        start: DateTime(2026, 10, 31),
        end: DateTime(2026, 11, 3, 23, 59),
        type: RepeatType.daily,
        days: const [],
        minutes: nineAm,
      );
      expect(out, [
        DateTime(2026, 10, 31, 9),
        DateTime(2026, 11, 1, 9),
        DateTime(2026, 11, 2, 9),
        DateTime(2026, 11, 3, 9),
      ]);
    });

    test('weekly occurrences stay on their weekday', () {
      // Sundays: Nov 1 and Nov 8, 2026.
      final out = occurrencesInRange(
        start: DateTime(2026, 10, 30),
        end: DateTime(2026, 11, 9, 23, 59),
        type: RepeatType.weekly,
        days: const [DateTime.sunday],
        minutes: nineAm,
      );
      expect(out, [DateTime(2026, 11, 1, 9), DateTime(2026, 11, 8, 9)]);
    });
  });

  group('across the March spring-forward day', () {
    test('daily occurrences: one per day at 09:00', () {
      final out = occurrencesInRange(
        start: DateTime(2026, 3, 7),
        end: DateTime(2026, 3, 10, 23, 59),
        type: RepeatType.daily,
        days: const [],
        minutes: nineAm,
      );
      expect(out, [
        DateTime(2026, 3, 7, 9),
        DateTime(2026, 3, 8, 9),
        DateTime(2026, 3, 9, 9),
        DateTime(2026, 3, 10, 9),
      ]);
    });

    test('every-3-days repeat keeps its rhythm after the change', () {
      // Anchored Mar 6 → Mar 6, Mar 9, Mar 12, …
      final next = nextOccurrence(
        from: DateTime(2026, 3, 9, 9, 1),
        type: RepeatType.interval,
        days: const [],
        minutes: nineAm,
        intervalDays: 3,
        anchorDate: DateTime(2026, 3, 6),
      );
      expect(next, DateTime(2026, 3, 12, 9));
    });
  });

  group('date_math helpers', () {
    test('addDays moves by calendar days and keeps the wall-clock time', () {
      expect(
        addDays(DateTime(2026, 10, 31, 9, 30), 1),
        DateTime(2026, 11, 1, 9, 30),
      );
      expect(
        addDays(DateTime(2026, 11, 1, 9, 30), 1),
        DateTime(2026, 11, 2, 9, 30),
      );
      expect(addDays(DateTime(2026, 3, 8, 9), -1), DateTime(2026, 3, 7, 9));
      expect(
        addDays(DateTime(2026, 12, 31, 23, 59), 1),
        DateTime(2027, 1, 1, 23, 59),
      );
    });

    test('addDays keeps UTC values in UTC', () {
      final out = addDays(DateTime.utc(2026, 11, 1, 6), 1);
      expect(out.isUtc, isTrue);
      expect(out, DateTime.utc(2026, 11, 2, 6));
    });

    test('daysBetween counts calendar days, ignoring hour shifts', () {
      expect(daysBetween(DateTime(2026, 10, 30), DateTime(2026, 11, 2, 23)), 3);
      expect(daysBetween(DateTime(2026, 3, 7, 23), DateTime(2026, 3, 9)), 2);
      expect(daysBetween(DateTime(2026, 11, 2), DateTime(2026, 10, 30)), -3);
    });
  });
}
