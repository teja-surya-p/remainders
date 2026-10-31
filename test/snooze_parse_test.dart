import 'package:flutter_test/flutter_test.dart';
import 'package:snooze_app/snooze_handler.dart';

void main() {
  group('SnoozeParse.parseCustom', () {
    final now = DateTime(2026, 6, 10, 14, 5);

    test('a number means minutes from now', () {
      expect(
        SnoozeParse.parseCustom('15', now: now),
        DateTime(2026, 6, 10, 14, 20),
      );
    });

    test('HH:MM later today stays today', () {
      expect(
        SnoozeParse.parseCustom('18:30', now: now),
        DateTime(2026, 6, 10, 18, 30),
      );
    });

    test('HH:MM already passed today means tomorrow', () {
      expect(
        SnoozeParse.parseCustom('09:30', now: now),
        DateTime(2026, 6, 11, 9, 30),
      );
    });

    test(
      'tomorrow keeps the typed clock time across the autumn DST change',
      () {
        // Regression: CI caught 09:30 becoming 08:30 when typed on the evening
        // before US clocks fall back (2026-11-01) — 24 hours != 1 calendar day.
        expect(
          SnoozeParse.parseCustom('09:30', now: DateTime(2026, 10, 31, 18, 21)),
          DateTime(2026, 11, 1, 9, 30),
        );
      },
    );

    test(
      'tomorrow keeps the typed clock time across the spring DST change',
      () {
        expect(
          SnoozeParse.parseCustom('07:00', now: DateTime(2026, 3, 7, 22)),
          DateTime(2026, 3, 8, 7),
        );
      },
    );

    test('rejects empty, zero, negative and malformed input', () {
      for (final bad in [
        '',
        '   ',
        '0',
        '-5',
        'soon',
        '25:00',
        '9:75',
        '12:5',
      ]) {
        expect(
          SnoozeParse.parseCustom(bad, now: now),
          isNull,
          reason: 'input "$bad"',
        );
      }
    });
  });
}
