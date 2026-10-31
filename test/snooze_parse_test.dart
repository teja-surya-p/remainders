import 'package:flutter_test/flutter_test.dart';
import 'package:snooze_app/snooze_handler.dart';

void main() {
  group('SnoozeParse.parseCustom', () {
    test('a number means minutes from now', () {
      final before = DateTime.now();
      final at = SnoozeParse.parseCustom('15')!;
      final minutes = at.difference(before).inSeconds / 60;
      expect(minutes, closeTo(15, 0.1));
    });

    test('HH:MM means the next time the clock shows it', () {
      final now = DateTime.now();
      final at = SnoozeParse.parseCustom('09:30')!;
      expect(at.hour, 9);
      expect(at.minute, 30);
      expect(at.isAfter(now), isTrue);
      expect(at.difference(now), lessThanOrEqualTo(const Duration(days: 1)));
    });

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
        expect(SnoozeParse.parseCustom(bad), isNull, reason: 'input "$bad"');
      }
    });
  });
}
