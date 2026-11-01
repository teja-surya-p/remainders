import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snooze_app/reminder_model.dart';
import 'package:snooze_app/storage/reminder_backup.dart';
import 'package:snooze_app/storage/sqlite_reminder_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

typedef FakeDoc = ({Map<String, dynamic> doc, int? at});

/// An in-memory backup server that stores real Firestore-shaped documents.
/// Every write gets the next "server time" ([FakeDoc.at]), which is what the
/// cursor counts; documents from older app versions have none.
class FakeRemote implements RemoteReminderBackup {
  int _clock = 0;
  final Map<String, FakeDoc> reminderDocs = {};
  final Map<String, FakeDoc> eventDocs = {};
  bool offline = false;
  bool rejectWrites = false;
  int fetches = 0;
  int docsRead = 0;
  int writes = 0;
  final List<void Function()> _queued = [];

  ReminderModel? reminder(String id) {
    final entry = reminderDocs[id];
    if (entry == null) return null;
    return FirestoreReminderBackup.reminderFromDoc(id, entry.doc)?.reminder;
  }

  /// A change made by another phone signed in to the same account.
  void writeFromOtherPhone(ReminderModel r) {
    reminderDocs[r.id] = (
      doc: FirestoreReminderBackup.reminderToDoc(_record(r)),
      at: ++_clock,
    );
  }

  /// Back online: queued writes reach the server, in order.
  void reconnect() {
    offline = false;
    final queued = List.of(_queued);
    _queued.clear();
    for (final apply in queued) {
      apply();
    }
  }

  @override
  Future<RemotePage<ReminderRecord>> fetchReminders({String? since}) =>
      _fetch(reminderDocs, since, FirestoreReminderBackup.reminderFromDoc);

  @override
  Future<RemotePage<ReminderEvent>> fetchEvents({String? since}) =>
      _fetch(eventDocs, since, FirestoreReminderBackup.eventFromDoc);

  @override
  Future<void> putReminder(ReminderRecord record) {
    final doc = FirestoreReminderBackup.reminderToDoc(record);
    return _write(() => reminderDocs[record.id] = (doc: doc, at: ++_clock));
  }

  @override
  Future<void> putEvent(ReminderEvent event) {
    final doc = event.toCloudMap();
    return _write(() => eventDocs[event.id] = (doc: doc, at: ++_clock));
  }

  Future<RemotePage<T>> _fetch<T>(
    Map<String, FakeDoc> docs,
    String? since,
    T? Function(String id, Map<String, dynamic> data) parse,
  ) async {
    if (offline) throw StateError('unavailable');
    fetches += 1;
    final after = since == null ? null : int.parse(since);
    var newest = after ?? 0;
    final items = <T>[];
    docs.forEach((id, entry) {
      final at = entry.at;
      // Like a Firestore range filter: documents without the field never
      // match, so older documents only come with a full download.
      if (after != null && (at == null || at <= after)) return;
      docsRead += 1;
      if (at != null) newest = max(newest, at);
      final item = parse(id, entry.doc);
      if (item != null) items.add(item);
    });
    return RemotePage(items, '$newest');
  }

  Future<void> _write(void Function() apply) {
    if (rejectWrites) return Future.error(StateError('permission-denied'));
    writes += 1;
    if (!offline) {
      apply();
      return Future.value();
    }
    final done = Completer<void>();
    _queued.add(() {
      apply();
      done.complete();
    });
    return done.future;
  }
}

ReminderRecord _record(ReminderModel r) => ReminderRecord(
  id: r.id,
  reminder: r,
  updatedAt: r.updatedAt,
  deleted: false,
);

DateTime d(int day) => DateTime(2026, 6, day, 9);

ReminderModel reminder(
  String id, {
  required DateTime due,
  String title = 'Take medicine',
  DateTime? updated,
}) => ReminderModel(
  id: id,
  title: title,
  dueAt: due,
  createdAt: DateTime(2026, 6, 1),
  updatedAt: updated ?? DateTime(2026, 6, 1),
);

ReminderEvent event(String id, String reminderId) => ReminderEvent(
  id: id,
  reminderId: reminderId,
  type: ReminderEventType.completed,
  scheduledAt: d(10),
  occurredAt: d(10),
);

/// Waits until [condition] holds (timers and database work run for real).
Future<void> eventually(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('condition never became true');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  setUpAll(sqfliteFfiInit);

  late Directory tmp;
  var phones = 0;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('snooze_backup_test');
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => tmp.delete(recursive: true));

  Future<SqliteReminderStore> phone() async {
    final store = SqliteReminderStore(
      factory: databaseFactoryFfi,
      path: p.join(tmp.path, 'phone${phones++}.db'),
    );
    await store.initialize();
    addTearDown(store.dispose);
    return store;
  }

  ReminderBackup backupFor(
    SqliteReminderStore store,
    FakeRemote remote, {
    String uid = 'user-1',
  }) {
    final backup = ReminderBackup(
      uid: uid,
      local: store,
      remote: remote,
      pushDelay: const Duration(milliseconds: 20),
      minSyncInterval: Duration.zero,
    );
    addTearDown(backup.dispose);
    return backup;
  }

  Future<BackupSyncResult?> sync(ReminderBackup backup) async {
    final result = await backup.syncNow(force: true);
    await backup.uploadsSettled();
    return result;
  }

  test('first sign-in uploads what is already on the phone', () async {
    final device = await phone();
    await device.upsertReminder(reminder('a', due: d(10)));
    await device.upsertReminder(reminder('b', due: d(11)));
    await device.upsertReminder(reminder('gone', due: d(12)));
    await device.deleteReminder('gone');
    await device.upsertEvent(event('e1', 'a'));
    final remote = FakeRemote();

    final result = await sync(backupFor(device, remote));

    // The deletion isn't sent: the backup never had that reminder.
    expect(result, (pulled: 0, pushed: 3));
    expect(remote.reminderDocs.keys, unorderedEquals(['a', 'b']));
    expect(remote.eventDocs.keys, ['e1']);
    expect(await device.listDirtyReminders(), isEmpty);
    expect(await device.listDirtyEvents(), isEmpty);
  });

  test('a new phone gets everything back', () async {
    final remote = FakeRemote();
    final oldPhone = await phone();
    await oldPhone.upsertReminder(reminder('a', due: d(10), title: 'Pills'));
    await oldPhone.upsertReminder(reminder('b', due: d(11)));
    await oldPhone.upsertEvent(event('e1', 'a'));
    final oldBackup = backupFor(oldPhone, remote);
    await sync(oldBackup);
    await oldPhone.deleteReminder('b');
    await sync(oldBackup);

    final newPhone = await phone();
    final result = await sync(backupFor(newPhone, remote));

    final restored = await newPhone.listReminders();
    expect(restored.single.title, 'Pills');
    expect(restored.single.dueAt, d(10));
    expect((await newPhone.listEvents()).single.id, 'e1');
    // What was restored matches the backup: nothing to send back.
    expect(result, (pulled: 2, pushed: 0));
    expect(await newPhone.listDirtyReminders(), isEmpty);
  });

  test('later syncs download only what changed', () async {
    final remote = FakeRemote();
    final device = await phone();
    for (final id in ['a', 'b', 'c']) {
      await device.upsertReminder(reminder(id, due: d(10)));
    }
    final backup = backupFor(device, remote);
    await sync(backup);
    // Our own uploads come back once, and change nothing.
    expect((await sync(backup))!.pulled, 0);

    remote.docsRead = 0;
    remote.writeFromOtherPhone(
      reminder('b', due: d(20), title: 'Moved', updated: DateTime(2026, 6, 2)),
    );
    final result = await sync(backup);

    expect(remote.docsRead, 1);
    expect(result!.pulled, 1);
    expect((await device.getReminder('b'))!.title, 'Moved');
  });

  test('the newer copy wins in both directions', () async {
    final remote = FakeRemote();
    final device = await phone();
    await device.upsertReminder(reminder('mine', due: d(10)));
    await device.upsertReminder(reminder('theirs', due: d(10)));
    final backup = backupFor(device, remote);
    await sync(backup);

    remote.writeFromOtherPhone(
      reminder(
        'mine',
        due: d(11),
        title: 'Older',
        updated: DateTime(2026, 6, 2),
      ),
    );
    await device.upsertReminder(
      reminder(
        'mine',
        due: d(12),
        title: 'Newer',
        updated: DateTime(2026, 6, 3),
      ),
    );
    remote.writeFromOtherPhone(
      reminder(
        'theirs',
        due: d(13),
        title: 'Edited',
        updated: DateTime(2026, 6, 4),
      ),
    );
    await sync(backup);

    expect((await device.getReminder('mine'))!.title, 'Newer');
    expect(remote.reminder('mine')!.title, 'Newer');
    expect((await device.getReminder('theirs'))!.title, 'Edited');
  });

  test('a deletion reaches the other phone and stays deleted', () async {
    final remote = FakeRemote();
    final phone1 = await phone();
    final phone2 = await phone();
    await phone1.upsertReminder(reminder('a', due: d(10)));
    final backup1 = backupFor(phone1, remote);
    final backup2 = backupFor(phone2, remote);
    await sync(backup1);
    await sync(backup2);
    expect(await phone2.getReminder('a'), isNotNull);

    await phone1.deleteReminder('a');
    await sync(backup1);
    await sync(backup2);
    expect(await phone2.listReminders(), isEmpty);
    expect(remote.reminderDocs['a']!.doc['title'], isNull);

    // A full download (e.g. signing in again later) doesn't bring it back.
    await phone2.writeMeta({ReminderBackup.metaAccount: null});
    await sync(backupFor(phone2, remote));
    expect(await phone2.listReminders(), isEmpty);
    final phone3 = await phone();
    await sync(backupFor(phone3, remote));
    expect(await phone3.listReminders(), isEmpty);
  });

  test('nothing is uploaded before the first full sync', () async {
    final remote = FakeRemote();
    remote.writeFromOtherPhone(
      reminder('a', due: d(20), title: 'Newer', updated: DateTime(2026, 6, 5)),
    );
    final device = await phone();
    await device.upsertReminder(reminder('a', due: d(10), title: 'Stale'));
    final backup = backupFor(device, remote);

    expect(await backup.pushNow(), 0);
    expect(remote.reminder('a')!.title, 'Newer');

    await sync(backup);
    expect((await device.getReminder('a'))!.title, 'Newer');
    expect(remote.writes, 0);
  });

  test('offline changes are kept and sent when back online', () async {
    final remote = FakeRemote();
    final device = await phone();
    final backup = backupFor(device, remote);
    await sync(backup);

    remote.offline = true;
    await device.upsertReminder(reminder('a', due: d(10)));
    await expectLater(backup.syncNow(force: true), throwsStateError);
    expect(await backup.pushNow(), 1);
    expect(await backup.pushNow(), 0, reason: 'already waiting to be sent');
    expect((await device.listDirtyReminders()).single.id, 'a');

    remote.reconnect();
    await backup.uploadsSettled();
    expect(remote.reminderDocs.keys, ['a']);
    expect(await device.listDirtyReminders(), isEmpty);
  });

  test('an edit made while its upload is in flight is sent too', () async {
    final remote = FakeRemote();
    final device = await phone();
    final backup = backupFor(device, remote);
    await sync(backup);

    remote.offline = true;
    final a = reminder('a', due: d(10));
    await device.upsertReminder(a);
    await backup.pushNow();
    await device.upsertReminder(a.copyWith(title: 'Edited'));
    remote.reconnect();
    await backup.uploadsSettled();
    expect((await device.listDirtyReminders()).single.id, 'a');

    await backup.pushNow();
    await backup.uploadsSettled();
    expect(remote.reminder('a')!.title, 'Edited');
    expect(await device.listDirtyReminders(), isEmpty);
  });

  test('quick changes are uploaded together, shortly after', () async {
    final remote = FakeRemote();
    final device = await phone();
    // Long enough that the edits below always land inside one delay.
    final backup = ReminderBackup(
      uid: 'user-1',
      local: device,
      remote: remote,
      pushDelay: const Duration(milliseconds: 300),
    );
    addTearDown(backup.dispose);
    await sync(backup);

    final a = reminder('a', due: d(10));
    await device.upsertReminder(a);
    backup.schedulePush();
    await device.upsertReminder(a.copyWith(title: 'Edited'));
    backup.schedulePush();
    await device.upsertReminder(reminder('b', due: d(11)));
    backup.schedulePush();
    expect(remote.writes, 0);

    await eventually(() => remote.writes == 2);
    await backup.uploadsSettled();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(remote.writes, 2);
    expect(remote.reminder('a')!.title, 'Edited');
  });

  test('rejected uploads stay pending and are retried', () async {
    final remote = FakeRemote();
    final device = await phone();
    final backup = backupFor(device, remote);
    await sync(backup);

    await device.upsertReminder(reminder('a', due: d(10)));
    remote.rejectWrites = true;
    await backup.pushNow();
    await backup.uploadsSettled();
    expect((await device.listDirtyReminders()).single.id, 'a');

    remote.rejectWrites = false;
    await backup.pushNow();
    await backup.uploadsSettled();
    expect(remote.reminderDocs.keys, ['a']);
    expect(await device.listDirtyReminders(), isEmpty);
  });

  test('signing in to another account backs the phone up there', () async {
    final device = await phone();
    await device.upsertReminder(reminder('a', due: d(10)));
    final first = FakeRemote();
    final second = FakeRemote();
    final backup1 = backupFor(device, first, uid: 'user-1');
    await sync(backup1);
    backup1.dispose();

    await sync(backupFor(device, second, uid: 'user-2'));
    expect(second.reminderDocs.keys, ['a']);
  });

  test('reminders backed up by older app versions are restored', () async {
    final remote = FakeRemote();
    final legacy = reminder('old', due: d(10), title: 'From the old app');
    remote.reminderDocs['old'] = (doc: legacy.toCloudMap(), at: null);
    final device = await phone();

    await sync(backupFor(device, remote));
    expect((await device.listReminders()).single.title, 'From the old app');
    expect(remote.writes, 0);
  });

  test('frequent automatic syncs only upload', () async {
    final remote = FakeRemote();
    final device = await phone();
    final backup = ReminderBackup(
      uid: 'user-1',
      local: device,
      remote: remote,
      minSyncInterval: const Duration(minutes: 1),
    );
    addTearDown(backup.dispose);
    await backup.syncNow();
    await device.upsertReminder(reminder('a', due: d(10)));

    await backup.syncNow();
    await backup.uploadsSettled();
    expect(remote.fetches, 2, reason: 'one sync: reminders and events');
    expect(remote.reminderDocs.keys, ['a']);
  });

  group('Firestore documents', () {
    test('a reminder survives the round trip', () {
      final r = reminder('a', due: d(10), title: 'Pills');
      final doc = FirestoreReminderBackup.reminderToDoc(_record(r));
      final back = FirestoreReminderBackup.reminderFromDoc('a', doc)!;
      expect(back.deleted, isFalse);
      expect(back.updatedAt, r.updatedAt);
      expect(back.reminder!.title, 'Pills');
      expect(back.reminder!.dueAt, d(10));
    });

    test('a deletion marker keeps no reminder data', () {
      final doc = FirestoreReminderBackup.reminderToDoc(
        ReminderRecord(
          id: 'a',
          reminder: null,
          updatedAt: DateTime(2026, 6, 3),
          deleted: true,
        ),
      );
      expect(doc.keys, unorderedEquals(['deleted', 'updatedAt']));
      expect(
        FirestoreReminderBackup.reminderFromDoc('a', doc)!.deleted,
        isTrue,
      );
    });

    test('unusable documents are skipped', () {
      expect(
        FirestoreReminderBackup.reminderFromDoc('x', {'title': 'No due time'}),
        isNull,
      );
      expect(
        FirestoreReminderBackup.eventFromDoc('x', {'type': 'completed'}),
        isNull,
      );
    });

    test('cursors round-trip, and an unreadable one means start over', () {
      final t = Timestamp(1790000000, 123456000);
      expect(
        FirestoreReminderBackup.decodeCursor(
          FirestoreReminderBackup.encodeCursor(t),
        ),
        t,
      );
      expect(FirestoreReminderBackup.decodeCursor('nonsense'), isNull);
      expect(FirestoreReminderBackup.decodeCursor(null), isNull);
    });
  });
}
