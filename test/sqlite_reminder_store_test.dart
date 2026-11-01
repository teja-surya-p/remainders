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

  ReminderRecord copy(
    ReminderModel? r, {
    String? id,
    required DateTime updatedAt,
    bool deleted = false,
  }) => ReminderRecord(
    id: id ?? r!.id,
    reminder: r,
    updatedAt: updatedAt,
    deleted: deleted,
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
      final changed = await store.applyRemote([
        copy(
          reminder('a', dueAt: DateTime(2026, 6, 12, 9), title: 'Renamed'),
          updatedAt: DateTime(2026, 6, 2),
        ),
      ]);
      expect(changed, 1);
      expect((await store.getReminder('a'))!.title, 'Renamed');
      // It came from the backup, so there is nothing to upload.
      expect(await store.listDirtyReminders(), isEmpty);
      await store.dispose();
    });

    test('an older backup copy is ignored and ours is re-uploaded', () async {
      final store = await openStore();
      await store.upsertReminder(
        reminder(
          'a',
          dueAt: DateTime(2026, 6, 10, 9),
          updatedAt: DateTime(2026, 6, 5),
        ),
      );
      final dirty = (await store.listDirtyReminders()).single.dirty;
      await store.markRemindersClean({'a': dirty});

      final changed = await store.applyRemote([
        copy(
          reminder('a', dueAt: DateTime(2026, 6, 12, 9), title: 'Old'),
          updatedAt: DateTime(2026, 6, 2),
        ),
      ]);
      expect(changed, 0);
      expect((await store.getReminder('a'))!.title, 'Take medicine');
      expect((await store.listDirtyReminders()).single.id, 'a');
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
      await store.applyRemote([
        copy(null, id: 'a', updatedAt: DateTime(2026, 6, 3), deleted: true),
      ]);
      expect(await store.listReminders(), isEmpty);
      await store.dispose();
    });

    test(
      'a deletion for a reminder this device never had is ignored',
      () async {
        final store = await openStore();
        final changed = await store.applyRemote([
          copy(null, id: 'x', updatedAt: DateTime(2026, 6, 3), deleted: true),
        ]);
        expect(changed, 0);
        expect(await store.listAllRows(), isEmpty);
        await store.dispose();
      },
    );

    test('a reminder only in the backup is restored', () async {
      final store = await openStore();
      await store.applyRemote([
        copy(
          reminder('z', dueAt: DateTime(2026, 6, 10, 9)),
          updatedAt: DateTime(2026, 6, 3),
        ),
      ]);
      expect((await store.listReminders()).single.id, 'z');
      await store.dispose();
    });
  });

  group('backup tracking', () {
    test('every local change needs uploading until confirmed', () async {
      final store = await openStore();
      final a = reminder('a', dueAt: DateTime(2026, 6, 10, 9));
      await store.upsertReminder(a);
      await store.upsertEvent(event('e1', 'a', DateTime(2026, 6, 10, 9)));

      final dirty = await store.listDirtyReminders();
      expect(dirty.single.id, 'a');
      final events = await store.listDirtyEvents();
      expect(events.single.event.id, 'e1');

      await store.markRemindersClean({'a': dirty.single.dirty});
      await store.markEventsClean({'e1': events.single.dirty});
      expect(await store.listDirtyReminders(), isEmpty);
      expect(await store.listDirtyEvents(), isEmpty);

      await store.deleteReminder('a');
      final tombstone = (await store.listDirtyReminders()).single;
      expect(tombstone.deleted, isTrue);
      await store.dispose();
    });

    test('a late confirmation does not hide a newer change', () async {
      final store = await openStore();
      final a = reminder('a', dueAt: DateTime(2026, 6, 10, 9));
      await store.upsertReminder(a);
      final first = (await store.listDirtyReminders()).single.dirty;
      await store.upsertReminder(a.copyWith(title: 'Edited'));
      // The upload of the first version is confirmed after the edit.
      await store.markRemindersClean({'a': first});
      final still = (await store.listDirtyReminders()).single;
      expect(still.reminder!.title, 'Edited');
      await store.dispose();
    });

    test('tombstones are purged only once the backup has them', () async {
      final store = await openStore();
      await store.upsertReminder(reminder('a', dueAt: DateTime(2026, 6, 10)));
      await store.deleteReminder('a');
      await store.purgeTombstones(olderThan: Duration.zero);
      expect(await store.listAllRows(), hasLength(1));

      final stamp = (await store.listDirtyReminders()).single.dirty;
      await store.markRemindersClean({'a': stamp});
      await store.purgeTombstones(olderThan: const Duration(days: 60));
      expect(await store.listAllRows(), hasLength(1));
      await store.purgeTombstones(olderThan: Duration.zero);
      expect(await store.listAllRows(), isEmpty);
      await store.dispose();
    });

    test('meta values are written together and removed with null', () async {
      final store = await openStore();
      await store.writeMeta({'backup_x': '1', 'backup_y': '2'});
      expect(await store.readMeta('backup_y'), '2');
      await store.writeMeta({'backup_x': null});
      expect(await store.readMeta('backup_x'), isNull);
      await store.dispose();
    });
  });

  test('a database from schema 1 is upgraded and backed up', () async {
    final path = p.join(tmp.path, 'old.db');
    final old = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        singleInstance: false,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE reminders (id TEXT PRIMARY KEY, data TEXT NOT NULL, '
            'due_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, '
            'deleted INTEGER NOT NULL DEFAULT 0)',
          );
          await db.execute(
            'CREATE TABLE events (id TEXT PRIMARY KEY, reminder_id TEXT NOT '
            'NULL, data TEXT NOT NULL, occurred_at INTEGER NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT)',
          );
        },
      ),
    );
    final a = reminder('a', dueAt: DateTime(2026, 6, 10, 9));
    await old.insert('reminders', {
      'id': 'a',
      'data': jsonEncode(a.toJson()),
      'due_at': a.dueAt.millisecondsSinceEpoch,
      'updated_at': a.updatedAt.millisecondsSinceEpoch,
      'deleted': 0,
    });
    await old.insert('meta', {'key': 'legacy_prefs_migrated', 'value': 'x'});
    await old.close();

    final store = await openStore(name: 'old.db');
    expect((await store.listReminders()).single.id, 'a');
    expect((await store.listDirtyReminders()).single.id, 'a');
    await store.dispose();
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
    await store.writeMeta({'backup_account': 'uid1'});
    await store.wipe();
    expect(await store.listAllRows(), isEmpty);
    expect(await store.listEvents(), isEmpty);
    expect(await store.readMeta('backup_account'), isNull);
    await store.dispose();
  });
}
