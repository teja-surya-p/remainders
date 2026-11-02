import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snooze_app/features.dart';
import 'package:snooze_app/reminder_model.dart';
import 'package:snooze_app/reminder_service.dart';
import 'package:snooze_app/storage/sqlite_reminder_store.dart';
import 'package:snooze_app/subscription_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late Directory tmp;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('snooze_service_test');
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => tmp.delete(recursive: true));

  test('v1 builds ship with the paywall, analytics and sharing off', () {
    expect(Features.paywall, isFalse);
    expect(Features.analytics, isFalse);
    expect(Features.sharing, isFalse);
  });

  test('with the paywall off there is no daily limit and every repeat '
      'type is allowed', () async {
    final service = ReminderService(subscription: SubscriptionService());
    await service.initialize(
      store: SqliteReminderStore(
        factory: databaseFactoryFfi,
        path: p.join(tmp.path, 'free.db'),
      ),
    );
    addTearDown(service.dispose);
    expect(service.isPremiumMode, isTrue);

    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final at = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 9);
    // The old free plan allowed 5 a day.
    for (var i = 0; i < 6; i++) {
      await service.createReminder(
        title: 'Reminder $i',
        dueAt: at.add(Duration(minutes: i)),
      );
    }
    // Formerly Pro-only: several weekdays and several times a day.
    await service.createReminder(
      title: 'Gym',
      dueAt: at,
      recurrence: ReminderRecurrence.fromJson({
        'type': 'weekly',
        'weekdays': [1, 3, 5],
        'timesOfDay': [9 * 60, 18 * 60],
      }),
    );
    expect(await service.listReminders(), hasLength(7));
  });

  test('a miss recorded by the app and the background job at once counts '
      'once', () async {
    // Two services on one database file, like the app and its background
    // re-arm job running at the same moment.
    final path = p.join(tmp.path, 'snooze.db');
    final store = SqliteReminderStore(factory: databaseFactoryFfi, path: path);
    final app = ReminderService(subscription: SubscriptionService());
    final job = ReminderService(subscription: SubscriptionService());
    await app.initialize(store: store);
    await job.initialize(
      store: SqliteReminderStore(factory: databaseFactoryFfi, path: path),
    );
    addTearDown(app.dispose);

    // A daily reminder whose occurrence an hour ago went unanswered.
    final now = DateTime.now();
    final hourAgo = now.subtract(const Duration(hours: 1));
    final due = DateTime(
      hourAgo.year,
      hourAgo.month,
      hourAgo.day,
      hourAgo.hour,
      hourAgo.minute,
    );
    await store.upsertReminder(
      ReminderModel(
        id: 'daily',
        title: 'Pills',
        dueAt: due,
        recurrence: ReminderRecurrence.fromJson({
          'type': 'daily',
          'timesOfDay': [due.hour * 60 + due.minute],
        }),
        createdAt: now.subtract(const Duration(days: 3)),
        updatedAt: now.subtract(const Duration(days: 3)),
      ),
    );

    await Future.wait([
      app.markReminderMissedOrAdvance('daily'),
      job.markReminderMissedOrAdvance('daily'),
    ]);

    final misses = (await store.listEvents()).where(
      (e) => e.type == ReminderEventType.missed,
    );
    expect(misses, hasLength(1));
    final moved = (await store.getReminder('daily'))!;
    expect(moved.dueAt.isAfter(now), isTrue);
    expect(moved.missedCount, 1);
  });
}
