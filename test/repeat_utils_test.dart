import 'package:flutter_test/flutter_test.dart';
import 'package:snooze_app/reminder_model.dart';
import 'package:snooze_app/repeat_utils.dart';

// Dates sit in June so no daylight-saving transition affects these cases in
// any time zone; DST behaviour gets its own tests with the M1 planner fix.
void main() {
  const nineAm = 9 * 60;
  const sixPm = 18 * 60;

  group('nextOccurrence', () {
    test('one-off returns the time later today', () {
      final from = DateTime(2026, 6, 10, 8);
      expect(
        nextOccurrence(
          from: from,
          type: RepeatType.none,
          days: const [],
          minutes: nineAm,
        ),
        DateTime(2026, 6, 10, 9),
      );
    });

    test('one-off returns null once its time has passed', () {
      final from = DateTime(2026, 6, 10, 10);
      expect(
        nextOccurrence(
          from: from,
          type: RepeatType.none,
          days: const [],
          minutes: nineAm,
        ),
        isNull,
      );
    });

    test('daily rolls over to tomorrow after today\'s time', () {
      final from = DateTime(2026, 6, 10, 9, 1);
      expect(
        nextOccurrence(
          from: from,
          type: RepeatType.daily,
          days: const [],
          minutes: nineAm,
        ),
        DateTime(2026, 6, 11, 9),
      );
    });

    test('daily fires at the exact due minute, not after it', () {
      final from = DateTime(2026, 6, 10, 9);
      expect(
        nextOccurrence(
          from: from,
          type: RepeatType.daily,
          days: const [],
          minutes: nineAm,
        ),
        DateTime(2026, 6, 10, 9),
      );
    });

    test('weekly picks the next allowed weekday', () {
      // 2026-06-10 is a Wednesday; allow Monday (1) and Friday (5).
      final from = DateTime(2026, 6, 10, 12);
      expect(
        nextOccurrence(
          from: from,
          type: RepeatType.weekly,
          days: const [DateTime.monday, DateTime.friday],
          minutes: nineAm,
        ),
        DateTime(2026, 6, 12, 9),
      );
    });

    test('weekly with no days never fires', () {
      expect(
        nextOccurrence(
          from: DateTime(2026, 6, 10),
          type: RepeatType.weekly,
          days: const [],
          minutes: nineAm,
        ),
        isNull,
      );
    });

    test('interval counts days from the anchor date', () {
      final from = DateTime(2026, 6, 11, 12);
      expect(
        nextOccurrence(
          from: from,
          type: RepeatType.interval,
          days: const [],
          minutes: nineAm,
          intervalDays: 3,
          anchorDate: DateTime(2026, 6, 10),
        ),
        DateTime(2026, 6, 13, 9),
      );
    });

    test('several times a day: picks the first one still ahead', () {
      final from = DateTime(2026, 6, 10, 12);
      expect(
        nextOccurrence(
          from: from,
          type: RepeatType.daily,
          days: const [],
          minutes: nineAm,
          timesOfDay: const [nineAm, sixPm],
        ),
        DateTime(2026, 6, 10, 18),
      );
    });

    test('stops after the end date', () {
      final from = DateTime(2026, 6, 10, 10);
      expect(
        nextOccurrence(
          from: from,
          type: RepeatType.daily,
          days: const [],
          minutes: nineAm,
          endAt: DateTime(2026, 6, 10, 23, 59),
        ),
        isNull,
      );
    });
  });

  group('occurrencesInRange', () {
    test('daily over three days gives three occurrences in order', () {
      final out = occurrencesInRange(
        start: DateTime(2026, 6, 10),
        end: DateTime(2026, 6, 12, 23, 59),
        type: RepeatType.daily,
        days: const [],
        minutes: nineAm,
      );
      expect(out, [
        DateTime(2026, 6, 10, 9),
        DateTime(2026, 6, 11, 9),
        DateTime(2026, 6, 12, 9),
      ]);
    });

    test('an end before the start gives nothing', () {
      expect(
        occurrencesInRange(
          start: DateTime(2026, 6, 12),
          end: DateTime(2026, 6, 10),
          type: RepeatType.daily,
          days: const [],
          minutes: nineAm,
        ),
        isEmpty,
      );
    });
  });

  group('parseRepeatDays', () {
    test('keeps valid weekdays, sorted and unique', () {
      expect(parseRepeatDays(<Object>[5, '1', 5, 0, -2, 'x']), [1, 5]);
    });

    test('non-lists give no days', () {
      expect(parseRepeatDays('1,2'), isEmpty);
    });
  });
}
