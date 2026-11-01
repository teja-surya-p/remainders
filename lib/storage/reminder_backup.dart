import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../reminder_model.dart';
import 'sqlite_reminder_store.dart';

/// Changes downloaded from the backup, and where the next download resumes.
class RemotePage<T> {
  const RemotePage(this.items, this.cursor);

  final List<T> items;

  /// Opaque position: pass it to the next fetch to get only later changes.
  final String cursor;
}

/// Where backups live: Firestore in the app, an in-memory fake in tests.
abstract class RemoteReminderBackup {
  /// Reminders and deletion markers changed after [since]; everything when
  /// [since] is null. Throws when the server can't be reached.
  Future<RemotePage<ReminderRecord>> fetchReminders({String? since});

  /// Events added after [since]; everything when [since] is null.
  Future<RemotePage<ReminderEvent>> fetchEvents({String? since});

  /// Completes once the server has the write. Writes made offline are kept
  /// and sent later, so never wait on this before carrying on.
  Future<void> putReminder(ReminderRecord record);

  Future<void> putEvent(ReminderEvent event);
}

/// Backups in Firestore: `users/{uid}/reminders/{id}` (reminders and
/// deletion markers) and `users/{uid}/reminderEvents/{id}`. Documents written
/// by earlier versions (no `deleted` or `serverUpdatedAt` field) still read.
class FirestoreReminderBackup implements RemoteReminderBackup {
  FirestoreReminderBackup({required String uid, FirebaseFirestore? firestore})
    : _reminders = (firestore ?? FirebaseFirestore.instance).collection(
        'users/$uid/reminders',
      ),
      _events = (firestore ?? FirebaseFirestore.instance).collection(
        'users/$uid/reminderEvents',
      );

  /// Set by the server on every write. After the first download, only
  /// documents changed since the newest value seen are fetched. (Device
  /// clocks can be wrong, so `updatedAt` can't serve for this.)
  static const String serverUpdatedAtField = 'serverUpdatedAt';

  final CollectionReference<Map<String, dynamic>> _reminders;
  final CollectionReference<Map<String, dynamic>> _events;

  @override
  Future<RemotePage<ReminderRecord>> fetchReminders({String? since}) =>
      _fetch(_reminders, since, reminderFromDoc);

  @override
  Future<RemotePage<ReminderEvent>> fetchEvents({String? since}) =>
      _fetch(_events, since, eventFromDoc);

  @override
  Future<void> putReminder(ReminderRecord record) =>
      _reminders.doc(record.id).set({
        ...reminderToDoc(record),
        serverUpdatedAtField: FieldValue.serverTimestamp(),
      });

  @override
  Future<void> putEvent(ReminderEvent event) => _events.doc(event.id).set({
    ...event.toCloudMap(),
    serverUpdatedAtField: FieldValue.serverTimestamp(),
  });

  Future<RemotePage<T>> _fetch<T>(
    CollectionReference<Map<String, dynamic>> collection,
    String? since,
    T? Function(String id, Map<String, dynamic> data) parse,
  ) async {
    final after = decodeCursor(since);
    final query = after == null
        ? collection
        : collection.where(serverUpdatedAtField, isGreaterThan: after);
    // Server only: an offline answer from the local cache could be stale,
    // and the cursor must only move past what the server confirmed.
    final snap = await query.get(const GetOptions(source: Source.server));
    var newest = after ?? Timestamp(0, 0);
    final items = <T>[];
    for (final doc in snap.docs) {
      final data = doc.data();
      final stamp = data[serverUpdatedAtField];
      if (stamp is Timestamp && stamp.compareTo(newest) > 0) newest = stamp;
      try {
        final item = parse(doc.id, data);
        if (item != null) items.add(item);
      } catch (e) {
        debugPrint('Skipping unreadable backup ${doc.id}: $e');
      }
    }
    return RemotePage(items, encodeCursor(newest));
  }

  /// The document for a reminder, or for a deletion marker (which keeps no
  /// reminder data). The server time is added when it is written.
  static Map<String, dynamic> reminderToDoc(ReminderRecord record) => {
    if (record.deleted)
      'deleted': true
    else ...{
      ...record.reminder!.toCloudMap(),
      'deleted': false,
    },
    // The row's version time, which is what newer-copy-wins compares.
    'updatedAt': Timestamp.fromDate(record.updatedAt),
  };

  /// Reads one reminder document; null if it can't be used.
  static ReminderRecord? reminderFromDoc(String id, Map<String, dynamic> data) {
    final stamp = data['updatedAt'];
    // Without a version time, any local copy wins.
    final updatedAt = stamp is Timestamp
        ? stamp.toDate()
        : DateTime.fromMillisecondsSinceEpoch(0);
    if (data['deleted'] == true) {
      return ReminderRecord(
        id: id,
        reminder: null,
        updatedAt: updatedAt,
        deleted: true,
      );
    }
    // A reminder without a due time would ring at once: skip it.
    if (data['dueAt'] is! Timestamp) return null;
    return ReminderRecord(
      id: id,
      reminder: ReminderModel.fromCloudDoc(id, data),
      updatedAt: updatedAt,
      deleted: false,
    );
  }

  /// Reads one event document; null if it can't be used.
  static ReminderEvent? eventFromDoc(String id, Map<String, dynamic> data) {
    if (data['occurredAt'] is! Timestamp) return null;
    return ReminderEvent.fromCloudDoc(id, data);
  }

  @visibleForTesting
  static String encodeCursor(Timestamp t) => '${t.seconds}:${t.nanoseconds}';

  @visibleForTesting
  static Timestamp? decodeCursor(String? cursor) {
    final parts = cursor?.split(':');
    if (parts == null || parts.length != 2) return null;
    final seconds = int.tryParse(parts[0]);
    final nanos = int.tryParse(parts[1]);
    if (seconds == null || nanos == null) return null;
    return Timestamp(seconds, nanos);
  }
}

typedef BackupSyncResult = ({int pulled, int pushed});

/// Keeps the signed-in account's backup in step with this device.
///
/// The device database stays the source of truth. Every local change marks
/// its row dirty (see [SqliteReminderStore]), whichever isolate made it.
/// A sync downloads what changed in the backup since the last sync, keeps
/// the newer copy of each reminder (deletions included), then uploads every
/// dirty row. The first sync with an account on this device downloads the
/// whole backup instead: a new phone gets everything back, and signing in
/// backs up what was already on the phone.
class ReminderBackup {
  ReminderBackup({
    required this.uid,
    required this.local,
    required this.remote,
    this.pushDelay = const Duration(seconds: 2),
    this.minSyncInterval = const Duration(minutes: 1),
  });

  final String uid;
  final SqliteReminderStore local;
  final RemoteReminderBackup remote;

  /// How long uploads wait after a change, to batch quick edits together.
  final Duration pushDelay;

  /// Automatic syncs (e.g. on every app resume) closer together than this
  /// only upload; they don't download again.
  final Duration minSyncInterval;

  static const String metaAccount = 'backup_account';
  static const String metaRemindersCursor = 'backup_reminders_cursor';
  static const String metaEventsCursor = 'backup_events_cursor';
  static const String metaLastSync = 'backup_last_sync';

  // id → stamp of uploads waiting for the server, so they aren't sent twice.
  final Map<String, int> _uploadingReminders = {};
  final Map<String, int> _uploadingEvents = {};
  final Set<Future<void>> _inFlight = {};
  Timer? _pushTimer;
  Future<BackupSyncResult?>? _syncing;
  DateTime? _lastSync;
  bool _synced = false;
  bool _disposed = false;

  /// Downloads changes from the backup, then uploads local ones. Concurrent
  /// calls share one run. Throws if the server can't be reached.
  Future<BackupSyncResult?> syncNow({bool force = false}) async {
    if (_disposed) return null;
    final last = _lastSync;
    if (!force &&
        last != null &&
        DateTime.now().difference(last) < minSyncInterval) {
      return (pulled: 0, pushed: await pushNow());
    }
    return _syncing ??= _sync().whenComplete(() => _syncing = null);
  }

  Future<BackupSyncResult?> _sync() async {
    final sameAccount = await local.readMeta(metaAccount) == uid;
    final remindersSince = sameAccount
        ? await local.readMeta(metaRemindersCursor)
        : null;
    final eventsSince = sameAccount
        ? await local.readMeta(metaEventsCursor)
        : null;

    final reminders = await remote.fetchReminders(since: remindersSince);
    final events = await remote.fetchEvents(since: eventsSince);
    if (_disposed) return null;

    var pulled = await local.applyRemote(reminders.items);
    if (remindersSince == null) {
      await local.reconcileReminders({
        for (final r in reminders.items) r.id: r.updatedAt,
      });
    }
    pulled += await local.applyRemoteEvents(events.items);
    if (eventsSince == null) {
      await local.reconcileEvents({for (final e in events.items) e.id});
    }
    if (_disposed) return null;

    final now = DateTime.now();
    await local.writeMeta({
      metaAccount: uid,
      metaRemindersCursor: reminders.cursor,
      metaEventsCursor: events.cursor,
      metaLastSync: now.toIso8601String(),
    });
    _lastSync = now;
    _synced = true;

    final pushed = await pushNow();
    await local.purgeTombstones();
    return (pulled: pulled, pushed: pushed);
  }

  /// Call after a local change: uploads shortly, batched with any other
  /// changes made in the meantime.
  void schedulePush() {
    if (_disposed) return;
    _pushTimer?.cancel();
    _pushTimer = Timer(pushDelay, () {
      unawaited(
        pushNow().catchError((Object e) {
          debugPrint('Backup upload failed: $e');
          return 0;
        }),
      );
    });
  }

  /// Sends every change the backup hasn't confirmed and returns how many
  /// were sent. Doesn't wait for the server: each row is marked backed up
  /// when its write is confirmed, so offline changes stay queued.
  Future<int> pushNow() async {
    _pushTimer?.cancel();
    if (_disposed || !await _hasSynced()) return 0;
    var sent = 0;
    for (final record in await local.listDirtyReminders()) {
      // Unreadable rows stay dirty (and untouched) rather than overwrite the
      // backup's good copy.
      if (!record.deleted && record.reminder == null) continue;
      if (_uploadingReminders[record.id] == record.dirty) continue;
      sent += 1;
      _upload(
        _uploadingReminders,
        record.id,
        record.dirty,
        () => remote.putReminder(record),
        () => local.markRemindersClean({record.id: record.dirty}),
      );
    }
    for (final item in await local.listDirtyEvents()) {
      final id = item.event.id;
      if (_uploadingEvents[id] == item.dirty) continue;
      sent += 1;
      _upload(
        _uploadingEvents,
        id,
        item.dirty,
        () => remote.putEvent(item.event),
        () => local.markEventsClean({id: item.dirty}),
      );
    }
    return sent;
  }

  void _upload(
    Map<String, int> uploading,
    String id,
    int stamp,
    Future<void> Function() put,
    Future<void> Function() markClean,
  ) {
    uploading[id] = stamp;
    // Future.sync: a put that throws at once fails this future instead.
    final upload = Future<void>.sync(put)
        .then((_) async {
          // After sign-out the row may belong to the next account's backup.
          if (!_disposed) await markClean();
        })
        .catchError((Object e) {
          debugPrint('Backup upload of $id failed: $e');
        })
        .whenComplete(() {
          if (uploading[id] == stamp) uploading.remove(id);
        });
    _inFlight.add(upload);
    unawaited(
      upload.whenComplete(() {
        _inFlight.remove(upload);
      }),
    );
  }

  /// Completes once every upload sent so far is confirmed or has failed.
  /// (Offline, that is when the connection comes back.)
  Future<void> uploadsSettled() => Future.wait(_inFlight.toList());

  /// Uploads wait for the first complete sync with this account on this
  /// device. Before it, dirty rows include reminders from before sign-in,
  /// and uploading one could overwrite a newer copy from another phone.
  Future<bool> _hasSynced() async {
    if (_synced) return true;
    return _synced = await local.readMeta(metaAccount) == uid;
  }

  /// Stops syncing (sign-out). Unconfirmed changes stay dirty on the device.
  void dispose() {
    _disposed = true;
    _pushTimer?.cancel();
  }

  /// When this device last finished a sync, if ever.
  static Future<DateTime?> lastSyncedAt(SqliteReminderStore store) async {
    final value = await store.readMeta(metaLastSync);
    return value == null ? null : DateTime.tryParse(value);
  }
}
