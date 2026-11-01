import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snooze_app/reminder_model.dart';
import 'package:snooze_app/storage/sqlite_reminder_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

ReminderModel reminder(
  String id, {
  required DateTime dueAt,
  DateTime? updatedAt,
  String title = 'Take medicine',
}) {
  final stamp = updatedAt ?? DateTime(2026, 6, 1);
  return ReminderModel(
    id: id,
    title: title,
    dueAt: dueAt,
    createdAt: DateTime(2026, 6, 1),
    updatedAt: stamp,
  );
}

ReminderEvent event(String id, String reminderId, DateTime at) => ReminderEvent(
  id: id,
  reminderId: reminderId,
  type: ReminderEventType.completed,
  scheduledAt: at,
  occurredAt: at,
);

void main() {
  setUpAll(sqfliteFfiInit);

  late Directory tmp;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('snooze_store_test');
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => tmp.delete(recursive: true));

  Future<SqliteReminderStore> openStore({String name = 'test.db'}) async {
    final store = SqliteReminderStore(
      factory: databaseFactoryFfi,
      path: p.join(tmp.path, name),
    );
    await store.initialize();
    return store;
  }

  test('stores reminders and lists them by due time', () async {
    final store = await openStore();
    await store.upsertReminder(reminder('b', dueAt: DateTime(2026, 6, 11, 9)));
    await store.upsertReminder(reminder('a', dueAt: DateTime(2026, 6, 10, 9)));
    expect((await store.listReminders()).map((r) => r.id), ['a', 'b']);
    expect((await store.getReminder('b'))!.dueAt, DateTime(2026, 6, 11, 9));
    await store.dispose();
  });

  test('notifies listeners after a change', () async {
    final store = await openStore();
    final next = store.watchReminders().first;
    await store.upsertReminder(reminder('a', dueAt: DateTime(2026, 6, 10, 9)));
    expect((await next).single.id, 'a');
    await store.dispose();
  });

  test(
    'delete keeps a tombstone for the backup but hides the reminder',
    () async {
      final store = await openStore();
      await store.upsertReminder(
        reminder('a', dueAt: DateTime(2026, 6, 10, 9)),
      );
      await store.deleteReminder('a');
      expect(await store.listReminders(), isEmpty);
      expect(await store.getReminder('a'), isNull);
      final rows = await store.listAllRows();
      expect(rows.single.deleted, isTrue);
      expect(rows.single.reminder, isNull);
      await store.dispose();
    },
  );

  group('applyRemote', () {
    test('a newer backup copy replaces the local one', () async {
      final store = await openStore();
      await store.upsertReminder(
        reminder(
          'a',
          dueAt: DateTime(2026, 6, 10, 9),
          updatedAt: DateTime(2026, 6, 1),
        ),
      );
      final changed = await store.applyRemote(
        id: 'a',
        updatedAt: DateTime(2026, 6, 2),
        deleted: false,
        reminder: reminder(
          'a',
          dueAt: DateTime(2026, 6, 12, 9),
          title: 'Renamed',
        ),
      );
      expect(changed, isTrue);
      expect((await store.getReminder('a'))!.title, 'Renamed');
      await store.dispose();
    });

    test('an older backup copy is ignored', () async {
      final store = await openStore();
      await store.upsertReminder(
        reminder(
          'a',
          dueAt: DateTime(2026, 6, 10, 9),
          updatedAt: DateTime(2026, 6, 5),
        ),
      );
      final changed = await store.applyRemote(
        id: 'a',
        updatedAt: DateTime(2026, 6, 2),
        deleted: false,
        reminder: reminder('a', dueAt: DateTime(2026, 6, 12, 9), title: 'Old'),
      );
      expect(changed, isFalse);
      expect((await store.getReminder('a'))!.title, 'Take medicine');
      await store.dispose();
    });

    test('a newer remote deletion removes the local reminder', () async {
      final store = await openStore();
      await store.upsertReminder(
        reminder(
          'a',
          dueAt: DateTime(2026, 6, 10, 9),
          updatedAt: DateTime(2026, 6, 1),
        ),
      );
      await store.applyRemote(
        id: 'a',
        updatedAt: DateTime(2026, 6, 3),
        deleted: true,
      );
      expect(await store.listReminders(), isEmpty);
      await store.dispose();
    });

    test('a reminder only in the backup is restored', () async {
      final store = await openStore();
      await store.applyRemote(
        id: 'z',
        updatedAt: DateTime(2026, 6, 3),
        deleted: false,
        reminder: reminder('z', dueAt: DateTime(2026, 6, 10, 9)),
      );
      expect((await store.listReminders()).single.id, 'z');
      await store.dispose();
    });
  });

  test('one unreadable reminder is skipped, the rest still load', () async {
    final store = await openStore();
    await store.upsertReminder(
      reminder('good', dueAt: DateTime(2026, 6, 10, 9)),
    );
    // Corrupt a row directly, as a bad write from an old version might.
    // A separate (non-shared) connection; closing a shared one would close
    // the store's connection too.
    final raw = await databaseFactoryFfi.openDatabase(
      p.join(tmp.path, 'test.db'),
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await raw.insert('reminders', {
      'id': 'bad',
      'data': '{not json',
      'due_at': 0,
      'updated_at': 0,
      'deleted': 0,
    });
    await raw.close();
    expect((await store.listReminders()).map((r) => r.id), ['good']);
    await store.dispose();
  });

  test('events are stored newest first', () async {
    final store = await openStore();
    await store.upsertEvents([
      event('e1', 'a', DateTime(2026, 6, 10, 9)),
      event('e2', 'a', DateTime(2026, 6, 11, 9)),
    ]);
    expect((await store.listEvents()).map((e) => e.id), ['e2', 'e1']);
    await store.dispose();
  });

  test('reminders saved by older versions are migrated once', () async {
    final r1 = reminder('r1', dueAt: DateTime(2026, 6, 10, 9));
    final r2 = reminder('r2', dueAt: DateTime(2026, 6, 11, 9));
    SharedPreferences.setMockInitialValues({
      'local_reminders_uid1': jsonEncode([r1.toJson(), r2.toJson()]),
      'local_reminder_events_uid1': jsonEncode([
        event('e1', 'r1', DateTime(2026, 6, 9)).toJson(),
      ]),
      'unrelated_key': 'value',
    });
    final store = await openStore();
    expect((await store.listReminders()).map((r) => r.id), ['r1', 'r2']);
    expect((await store.listEvents()).single.id, 'e1');

    // Deleting after migration must stick: the next launch must not
    // re-import the old copy.
    await store.deleteReminder('r1');
    await store.dispose();
    final reopened = await openStore();
    expect((await reopened.listReminders()).map((r) => r.id), ['r2']);
    await reopened.dispose();
  });

  test('wipe deletes everything on the device', () async {
    final store = await openStore();
    await store.upsertReminder(reminder('a', dueAt: DateTime(2026, 6, 10, 9)));
    await store.upsertEvent(event('e1', 'a', DateTime(2026, 6, 10, 9)));
    await store.wipe();
    expect(await store.listAllRows(), isEmpty);
    expect(await store.listEvents(), isEmpty);
    await store.dispose();
  });
}
