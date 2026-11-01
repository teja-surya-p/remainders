import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../reminder_model.dart';
import '../reminder_store.dart';

/// One reminder record: the reminder itself, or a deletion marker
/// ("tombstone") that tells other devices it was deleted. Used both for the
/// rows on this device and for the copies in the backup.
class ReminderRecord {
  final String id;

  /// Null for a tombstone or a row whose data could not be read.
  final ReminderModel? reminder;
  final DateTime updatedAt;
  final bool deleted;

  /// 0 once the backup has this version; otherwise a stamp identifying the
  /// newest change the backup hasn't confirmed yet. Always 0 for backup copies.
  final int dirty;

  const ReminderRecord({
    required this.id,
    required this.reminder,
    required this.updatedAt,
    required this.deleted,
    this.dirty = 0,
  });
}

/// An event the backup hasn't confirmed yet, with its change stamp.
typedef DirtyEvent = ({ReminderEvent event, int dirty});

/// The device's reminders, stored in SQLite. This is the source of truth for
/// everyone, signed in or not; the cloud is only a backup.
///
/// Each reminder is its own row, written atomically in a transaction, so:
/// - the app and its background isolates (notification actions, re-arm jobs)
///   can't overwrite each other's changes the way one shared JSON blob could;
/// - one unreadable reminder is skipped instead of losing the whole list.
///
/// Every local write stamps its row "dirty" (whichever isolate made it), so
/// the backup knows what to upload without keeping its own list.
class SqliteReminderStore implements ReminderStore {
  SqliteReminderStore({
    DatabaseFactory? factory,
    String? path,
    Future<SharedPreferences> Function()? legacyPrefs,
  }) : _factory = factory ?? databaseFactory,
       _path = path,
       _legacyPrefs = legacyPrefs ?? SharedPreferences.getInstance;

  static const String fileName = 'snooze.db';
  static const int _schemaVersion = 2;
  static const String _legacyRemindersPrefix = 'local_reminders_';
  static const String _legacyEventsPrefix = 'local_reminder_events_';
  static const String _metaLegacyMigrated = 'legacy_prefs_migrated';

  final DatabaseFactory _factory;
  final String? _path;
  final Future<SharedPreferences> Function() _legacyPrefs;

  Database? _db;
  Future<void>? _opening;
  int _lastStamp = 0;
  final StreamController<List<ReminderModel>> _remindersController =
      StreamController<List<ReminderModel>>.broadcast();
  final StreamController<List<ReminderEvent>> _eventsController =
      StreamController<List<ReminderEvent>>.broadcast();

  @override
  Future<void> initialize() => _opening ??= _open();

  Future<void> _open() async {
    final path = _path ?? p.join(await _factory.getDatabasesPath(), fileName);
    _db = await _factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: _schemaVersion,
        onConfigure: (db) async {
          // The app and its background isolates (notification actions, the
          // re-arm job) can open this file at the same moment, e.g. right
          // after an update: writers wait for each other instead of failing.
          // (Android's SQLite manages the journal mode itself; changing it by
          // hand breaks its transactions, so it is left alone.)
          await db.rawQuery('PRAGMA busy_timeout=5000');
        },
        onCreate: (db, _) async {
          // IF NOT EXISTS: two isolates may race to create a fresh database.
          await db.execute('''
            CREATE TABLE IF NOT EXISTS reminders (
              id TEXT PRIMARY KEY,
              data TEXT NOT NULL,
              due_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              deleted INTEGER NOT NULL DEFAULT 0,
              dirty INTEGER NOT NULL DEFAULT 1
            )''');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS events (
              id TEXT PRIMARY KEY,
              reminder_id TEXT NOT NULL,
              data TEXT NOT NULL,
              occurred_at INTEGER NOT NULL,
              dirty INTEGER NOT NULL DEFAULT 1
            )''');
          await db.execute(
            'CREATE INDEX IF NOT EXISTS events_by_reminder ON events(reminder_id)',
          );
          await db.execute(
            'CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT)',
          );
        },
        onUpgrade: (db, oldVersion, _) async {
          if (oldVersion < 2) {
            // Backup tracking. Everything already saved still needs backing
            // up, hence the default of 1 (dirty).
            await _addColumn(
              db,
              'reminders',
              'dirty INTEGER NOT NULL DEFAULT 1',
            );
            await _addColumn(db, 'events', 'dirty INTEGER NOT NULL DEFAULT 1');
          }
        },
      ),
    );
    await _migrateLegacyPrefs();
  }

  static Future<void> _addColumn(
    DatabaseExecutor db,
    String table,
    String definition,
  ) async {
    final name = definition.split(' ').first;
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    if (columns.any((c) => c['name'] == name)) return;
    await db.execute('ALTER TABLE $table ADD COLUMN $definition');
  }

  Database get _database {
    final db = _db;
    if (db == null) {
      throw StateError('Reminder store used before initialize().');
    }
    return db;
  }

  /// A new, increasing stamp for a change the backup hasn't confirmed.
  int _nextStamp() {
    final now = DateTime.now().microsecondsSinceEpoch;
    _lastStamp = now > _lastStamp ? now : _lastStamp + 1;
    return _lastStamp;
  }

  // ---------------------------------------------------------------- reminders

  @override
  Stream<List<ReminderModel>> watchReminders() => _remindersController.stream;

  @override
  Future<List<ReminderModel>> listReminders() async {
    final rows = await _database.query(
      'reminders',
      columns: ['id', 'data'],
      where: 'deleted = 0',
      orderBy: 'due_at',
    );
    return [
      for (final row in rows)
        ?_decodeReminder(row['data'] as String, row['id']),
    ];
  }

  @override
  Future<ReminderModel?> getReminder(String id) async {
    final rows = await _database.query(
      'reminders',
      columns: ['data'],
      where: 'id = ? AND deleted = 0',
      whereArgs: [id],
    );
    if (rows.isEmpty) return null;
    return _decodeReminder(rows.first['data'] as String, id);
  }

  @override
  Future<void> upsertReminder(ReminderModel reminder) async {
    await _database.insert(
      'reminders',
      _reminderRow(reminder, dirty: _nextStamp()),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _emitReminders();
  }

  @override
  Future<void> upsertReminders(List<ReminderModel> reminders) async {
    if (reminders.isEmpty) return;
    await _database.transaction((txn) async {
      final batch = txn.batch();
      for (final reminder in reminders) {
        batch.insert(
          'reminders',
          _reminderRow(reminder, dirty: _nextStamp()),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
    await _emitReminders();
  }

  /// Marks the reminder deleted. Its contents are dropped; a tombstone stays
  /// so the backup can delete it on other devices too.
  @override
  Future<void> deleteReminder(String id) async {
    await _database.update(
      'reminders',
      {
        'deleted': 1,
        'data': '{}',
        'updated_at': DateTime.now().millisecondsSinceEpoch,
        'dirty': _nextStamp(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await _emitReminders();
  }

  // ------------------------------------------------------------------- events

  @override
  Stream<List<ReminderEvent>> watchEvents() => _eventsController.stream;

  @override
  Future<List<ReminderEvent>> listEvents() async {
    final rows = await _database.query(
      'events',
      columns: ['id', 'data'],
      orderBy: 'occurred_at DESC',
    );
    final out = <ReminderEvent>[];
    for (final row in rows) {
      final event = _decodeEvent(row['data'] as String, row['id']);
      if (event != null) out.add(event);
    }
    return out;
  }

  @override
  Future<void> upsertEvent(ReminderEvent event) => upsertEvents([event]);

  @override
  Future<void> upsertEvents(List<ReminderEvent> events) async {
    if (events.isEmpty) return;
    await _database.transaction((txn) async {
      final batch = txn.batch();
      for (final event in events) {
        batch.insert(
          'events',
          _eventRow(event, dirty: _nextStamp()),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
    await _emitEvents();
  }

  // ------------------------------------------------------------------- backup

  /// Every reminder row, tombstones included.
  Future<List<ReminderRecord>> listAllRows() async {
    final rows = await _database.query('reminders');
    return [for (final row in rows) _record(row)];
  }

  /// Rows (tombstones included) with changes the backup hasn't confirmed.
  Future<List<ReminderRecord>> listDirtyReminders() async {
    final rows = await _database.query('reminders', where: 'dirty != 0');
    return [for (final row in rows) _record(row)];
  }

  /// Events the backup hasn't confirmed.
  Future<List<DirtyEvent>> listDirtyEvents() async {
    final rows = await _database.query(
      'events',
      columns: ['id', 'data', 'dirty'],
      where: 'dirty != 0',
    );
    return [
      for (final row in rows)
        if (_decodeEvent(row['data'] as String, row['id']) case final event?)
          (event: event, dirty: row['dirty'] as int),
    ];
  }

  /// Records that the backup confirmed these versions (id → stamp). A row
  /// changed again since then has a new stamp and stays dirty.
  Future<void> markRemindersClean(Map<String, int> stamps) =>
      _markClean('reminders', stamps);

  Future<void> markEventsClean(Map<String, int> stamps) =>
      _markClean('events', stamps);

  Future<void> _markClean(String table, Map<String, int> stamps) async {
    if (stamps.isEmpty) return;
    final batch = _database.batch();
    stamps.forEach((id, stamp) {
      batch.update(
        table,
        {'dirty': 0},
        where: 'id = ? AND dirty = ?',
        whereArgs: [id, stamp],
      );
    });
    await batch.commit(noResult: true);
  }

  /// Applies copies from the backup. Each replaces the local row only if it
  /// is newer, deletions included; a local row newer than its backup copy is
  /// marked for upload again. Returns how many local rows changed.
  Future<int> applyRemote(Iterable<ReminderRecord> records) async {
    final list = records.toList();
    if (list.isEmpty) return 0;
    final changed = await _database.transaction((txn) async {
      var count = 0;
      for (final record in list) {
        if (await _applyRemoteRecord(txn, record)) count += 1;
      }
      return count;
    }, exclusive: true);
    if (changed > 0) await _emitReminders();
    return changed;
  }

  Future<bool> _applyRemoteRecord(
    Transaction txn,
    ReminderRecord record,
  ) async {
    final remoteUpdated = record.updatedAt.millisecondsSinceEpoch;
    final existing = await txn.query(
      'reminders',
      columns: ['updated_at', 'dirty'],
      where: 'id = ?',
      whereArgs: [record.id],
    );
    if (existing.isNotEmpty) {
      final localUpdated = existing.first['updated_at'] as int;
      if (localUpdated > remoteUpdated) {
        // The backup has an older version: upload this one again.
        if (existing.first['dirty'] as int == 0) {
          await txn.update(
            'reminders',
            {'dirty': _nextStamp()},
            where: 'id = ?',
            whereArgs: [record.id],
          );
        }
        return false;
      }
      if (localUpdated == remoteUpdated) return false;
    }

    if (record.deleted) {
      if (existing.isEmpty) return false; // nothing here to delete
      await txn.update(
        'reminders',
        {'deleted': 1, 'data': '{}', 'updated_at': remoteUpdated, 'dirty': 0},
        where: 'id = ?',
        whereArgs: [record.id],
      );
      return true;
    }
    final reminder = record.reminder;
    if (reminder == null) return false;
    await txn.insert('reminders', {
      ..._reminderRow(reminder, dirty: 0),
      'updated_at': remoteUpdated,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return true;
  }

  /// Adds events from the backup that this device doesn't have yet (events
  /// never change once written). Returns how many were added.
  Future<int> applyRemoteEvents(Iterable<ReminderEvent> events) async {
    final list = events.toList();
    if (list.isEmpty) return 0;
    final added = await _database.transaction((txn) async {
      var count = 0;
      for (final event in list) {
        final existing = await txn.query(
          'events',
          columns: ['id'],
          where: 'id = ?',
          whereArgs: [event.id],
        );
        if (existing.isNotEmpty) continue;
        await txn.insert('events', _eventRow(event, dirty: 0));
        count += 1;
      }
      return count;
    });
    if (added > 0) await _emitEvents();
    return added;
  }

  /// After downloading an account's whole backup (the first sync with that
  /// account on this device), marks each row as backed up if the backup has
  /// this version, or as needing upload if it doesn't. [backup] maps each
  /// backed-up id to its version time.
  Future<void> reconcileReminders(Map<String, DateTime> backup) async {
    await _database.transaction((txn) async {
      final rows = await txn.query(
        'reminders',
        columns: ['id', 'updated_at', 'deleted', 'dirty'],
      );
      final batch = txn.batch();
      for (final row in rows) {
        final id = row['id'] as String;
        final remote = backup[id]?.millisecondsSinceEpoch;
        final backedUp = remote == null
            // A deletion has nothing to delete in a backup that never had it.
            ? row['deleted'] as int == 1
            : remote >= (row['updated_at'] as int);
        _setDirty(batch, 'reminders', id, row['dirty'] as int, !backedUp);
      }
      await batch.commit(noResult: true);
    }, exclusive: true);
  }

  /// Like [reconcileReminders], for events: [backupIds] are the ids the
  /// backup already has.
  Future<void> reconcileEvents(Set<String> backupIds) async {
    await _database.transaction((txn) async {
      final rows = await txn.query('events', columns: ['id', 'dirty']);
      final batch = txn.batch();
      for (final row in rows) {
        final id = row['id'] as String;
        _setDirty(
          batch,
          'events',
          id,
          row['dirty'] as int,
          !backupIds.contains(id),
        );
      }
      await batch.commit(noResult: true);
    }, exclusive: true);
  }

  void _setDirty(
    Batch batch,
    String table,
    String id,
    int current,
    bool dirty,
  ) {
    if (dirty == (current != 0)) return;
    batch.update(
      table,
      {'dirty': dirty ? _nextStamp() : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Drops deletion markers the backup has confirmed, once old enough that
  /// every device has had the chance to sync them.
  Future<void> purgeTombstones({
    Duration olderThan = const Duration(days: 60),
  }) {
    final cutoff = DateTime.now().subtract(olderThan).millisecondsSinceEpoch;
    return _database.delete(
      'reminders',
      where: 'deleted = 1 AND dirty = 0 AND updated_at < ?',
      whereArgs: [cutoff],
    );
  }

  /// Small values the backup keeps between launches (cursors, account).
  Future<String?> readMeta(String key) async {
    final rows = await _database.query(
      'meta',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
    );
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  /// Writes all [values] at once; a null value removes the key.
  Future<void> writeMeta(Map<String, String?> values) async {
    final batch = _database.batch();
    values.forEach((key, value) {
      if (value == null) {
        batch.delete('meta', where: 'key = ?', whereArgs: [key]);
      } else {
        batch.insert('meta', {
          'key': key,
          'value': value,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
    await batch.commit(noResult: true);
  }

  // ------------------------------------------------------------ housekeeping

  /// Re-reads everything and notifies listeners, e.g. on app resume, to pick
  /// up changes another isolate saved while the app was in the background.
  Future<void> reload() async {
    await _emitReminders();
    await _emitEvents();
  }

  /// Deletes all reminders, history and backup state on this device.
  Future<void> wipe() async {
    await _database.transaction((txn) async {
      await txn.delete('reminders');
      await txn.delete('events');
      await txn.delete(
        'meta',
        where: 'key != ?',
        whereArgs: [_metaLegacyMigrated],
      );
    });
    await reload();
  }

  @override
  Future<void> dispose() async {
    await _remindersController.close();
    await _eventsController.close();
    await _db?.close();
    _db = null;
    _opening = null;
  }

  // ------------------------------------------------------------- internals

  Map<String, Object?> _reminderRow(
    ReminderModel reminder, {
    required int dirty,
  }) => {
    'id': reminder.id,
    'data': jsonEncode(reminder.toJson()),
    'due_at': reminder.dueAt.millisecondsSinceEpoch,
    'updated_at': reminder.updatedAt.millisecondsSinceEpoch,
    'deleted': 0,
    'dirty': dirty,
  };

  Map<String, Object?> _eventRow(ReminderEvent event, {required int dirty}) => {
    'id': event.id,
    'reminder_id': event.reminderId,
    'data': jsonEncode(event.toJson()),
    'occurred_at': event.occurredAt.millisecondsSinceEpoch,
    'dirty': dirty,
  };

  ReminderRecord _record(Map<String, Object?> row) {
    final deleted = (row['deleted'] as int) == 1;
    return ReminderRecord(
      id: row['id'] as String,
      reminder: deleted
          ? null
          : _decodeReminder(row['data'] as String, row['id']),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
      deleted: deleted,
      dirty: row['dirty'] as int,
    );
  }

  ReminderModel? _decodeReminder(String data, Object? id) {
    try {
      final reminder = ReminderModel.fromJson(_decodeMap(data));
      return reminder.id.isEmpty ? null : reminder;
    } catch (e) {
      // Left untouched in the database, so nothing is lost.
      debugPrint('Skipping unreadable reminder $id: $e');
      return null;
    }
  }

  ReminderEvent? _decodeEvent(String data, Object? id) {
    try {
      return ReminderEvent.fromJson(_decodeMap(data));
    } catch (e) {
      debugPrint('Skipping unreadable event $id: $e');
      return null;
    }
  }

  Map<String, dynamic> _decodeMap(String data) =>
      Map<String, dynamic>.from(jsonDecode(data) as Map);

  Future<void> _emitReminders() async {
    if (_remindersController.isClosed) return;
    _remindersController.add(await listReminders());
  }

  Future<void> _emitEvents() async {
    if (_eventsController.isClosed) return;
    _eventsController.add(await listEvents());
  }

  /// Imports reminders saved by earlier versions (one JSON blob per signed-in
  /// account in SharedPreferences) the first time the database opens. The old
  /// values are left in place as a safety net.
  Future<void> _migrateLegacyPrefs() async {
    final db = _database;
    final done = await db.query(
      'meta',
      where: 'key = ?',
      whereArgs: [_metaLegacyMigrated],
    );
    if (done.isNotEmpty) return;

    SharedPreferences prefs;
    try {
      prefs = await _legacyPrefs();
    } catch (e) {
      debugPrint('Legacy reminders not migrated (no preferences): $e');
      return;
    }

    final reminders = <String, ReminderModel>{};
    final events = <ReminderEvent>[];
    for (final key in prefs.getKeys()) {
      final raw = prefs.get(key);
      if (raw is! String) continue;
      if (key.startsWith(_legacyRemindersPrefix)) {
        for (final item in _legacyList(raw, key)) {
          try {
            final r = ReminderModel.fromJson(item);
            final existing = reminders[r.id];
            if (r.id.isNotEmpty &&
                (existing == null || r.updatedAt.isAfter(existing.updatedAt))) {
              reminders[r.id] = r;
            }
          } catch (e) {
            debugPrint('Skipping unreadable legacy reminder in $key: $e');
          }
        }
      } else if (key.startsWith(_legacyEventsPrefix)) {
        for (final item in _legacyList(raw, key)) {
          try {
            events.add(ReminderEvent.fromJson(item));
          } catch (e) {
            debugPrint('Skipping unreadable legacy event in $key: $e');
          }
        }
      }
    }

    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final r in reminders.values) {
        batch.insert(
          'reminders',
          _reminderRow(r, dirty: _nextStamp()),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      for (final e in events) {
        batch.insert(
          'events',
          _eventRow(e, dirty: _nextStamp()),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      // Another isolate may finish the same migration first.
      batch.insert('meta', {
        'key': _metaLegacyMigrated,
        'value': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await batch.commit(noResult: true);
    });
    if (reminders.isNotEmpty || events.isNotEmpty) {
      debugPrint(
        'Migrated ${reminders.length} reminders and ${events.length} events '
        'from the old storage.',
      );
    }
  }

  List<Map<String, dynamic>> _legacyList(String raw, String key) {
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return [
        for (final item in list)
          if (item is Map) Map<String, dynamic>.from(item),
      ];
    } catch (e) {
      debugPrint('Legacy data in $key could not be read: $e');
      return const [];
    }
  }
}
