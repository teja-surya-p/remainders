import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snooze_app/pages/profile_page.dart';

void main() {
  final now = DateTime(2026, 11, 1, 15);

  Future<String> describe(
    WidgetTester tester,
    DateTime at, {
    bool use24h = false,
  }) async {
    late String text;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(alwaysUse24HourFormat: use24h),
          child: Builder(
            builder: (context) {
              text = describeBackupTime(context, at, now: now);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    return text;
  }

  testWidgets('recent backups read as relative times', (tester) async {
    expect(
      await describe(tester, now.subtract(const Duration(seconds: 30))),
      'just now',
    );
    expect(
      await describe(tester, now.subtract(const Duration(minutes: 5))),
      '5 min ago',
    );
  });

  testWidgets("older backups follow the phone's clock format", (tester) async {
    final morning = DateTime(2026, 11, 1, 9, 50);
    expect(await describe(tester, morning), 'today at 9:50 AM');
    expect(await describe(tester, morning, use24h: true), 'today at 09:50');
    expect(
      await describe(tester, DateTime(2026, 10, 30, 21, 14), use24h: true),
      'on Fri, Oct 30 at 21:14',
    );
  });
}
