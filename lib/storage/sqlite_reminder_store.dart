import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../reminder_model.dart';
import '../reminder_store.dart';

/// One row of the reminders table, including deletion markers ("tombstones")
/// that the backup needs to tell other devices a reminder was deleted.
class StoredReminderRow {
  final String id;

  /// Null for a tombstone or a row whose data could not be read.
  final ReminderModel? reminder;
  final DateTime updatedAt;
  final bool deleted;

  const StoredReminderRow({
    required this.id,
    required this.reminder,
    required this.updatedAt,
    required this.deleted,
  });
}

/// The device's reminders, stored in SQLite. This is the source of truth for
/// everyone, signed in or not; the cloud is only a backup.
///
/// Each reminder is its own row, written atomically, so:
/// - the app and its background isolates (notification actions, re-arm jobs)
///   can't overwrite each other's changes the way one shared JSON blob could;
/// - one unreadable reminder is skipped instead of losing the whole list.
class SqliteReminderStore implements ReminderStore {
  SqliteReminderStore({
    DatabaseFactory? factory,
    String? path,
    Future<SharedPreferences> Function()? legacyPrefs,
  }) : _factory = factory ?? databaseFactory,
       _path = path,
       _legacyPrefs = legacyPrefs ?? SharedPreferences.getInstance;

  static const String fileName = 'snooze.db';
  static const int _schemaVersion = 1;
  static const String _legacyRemindersPrefix = 'local_reminders_';
  static const String _legacyEventsPrefix = 'local_reminder_events_';
  static const String _metaLegacyMigrated = 'legacy_prefs_migrated';

  final DatabaseFactory _factory;
  final String? _path;
  final Future<SharedPreferences> Function() _legacyPrefs;

  Database? _db;
  Future<void>? _opening;
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
          // Several isolates in this process open the same file: WAL lets them
          // read while another writes, and a busy timeout makes writers wait
          // instead of failing.
          await db.rawQuery('PRAGMA journal_mode=WAL');
          await db.rawQuery('PRAGMA busy_timeout=5000');
        },
        onCreate: (db, _) async {
          final batch = db.batch()
            ..execute('''
              CREATE TABLE reminders (
                id TEXT PRIMARY KEY,
                data TEXT NOT NULL,
                due_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                deleted INTEGER NOT NULL DEFAULT 0
              )''')
            ..execute('''
              CREATE TABLE events (
                id TEXT PRIMARY KEY,
                reminder_id TEXT NOT NULL,
                data TEXT NOT NULL,
                occurred_at INTEGER NOT NULL
              )''')
            ..execute('CREATE INDEX events_by_reminder ON events(reminder_id)')
            ..execute('CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT)');
          await batch.commit(noResult: true);
        },
      ),
    );
    await _migrateLegacyPrefs();
  }

  Database get _database {
    final db = _db;
    if (db == null) {
      throw StateError('Reminder store used before initialize().');
    }
    return db;
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
      _reminderRow(reminder),
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
          _reminderRow(reminder),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
    await _emitReminders();
  }

  /// Marks the reminder deleted (kept as a tombstone for the backup).
  @override
  Future<void> deleteReminder(String id) async {
    await _database.update(
      'reminders',
      {'deleted': 1, 'updated_at': DateTime.now().millisecondsSinceEpoch},
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
      try {
        out.add(ReminderEvent.fromJson(_decodeMap(row['data'] as String)));
      } catch (e) {
        debugPrint('Skipping unreadable event ${row['id']}: $e');
      }
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
        batch.insert('events', {
          'id': event.id,
          'reminder_id': event.reminderId,
          'data': jsonEncode(event.toJson()),
          'occurred_at': event.occurredAt.millisecondsSinceEpoch,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
    await _emitEvents();
  }

  // ------------------------------------------------- backup & housekeeping

  /// Every reminder row, tombstones included.
  Future<List<StoredReminderRow>> listAllRows() async {
    final rows = await _database.query('reminders');
    return [
      for (final row in rows)
        StoredReminderRow(
          id: row['id'] as String,
          reminder: (row['deleted'] as int) == 1
              ? null
              : _decodeReminder(row['data'] as String, row['id']),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(
            row['updated_at'] as int,
          ),
          deleted: (row['deleted'] as int) == 1,
        ),
    ];
  }

  /// Applies a reminder (or a deletion) from the backup if it is newer than
  /// what this device has. Returns true when the local copy changed.
  Future<bool> applyRemote({
    required String id,
    required DateTime updatedAt,
    required bool deleted,
    ReminderModel? reminder,
  }) async {
    final changed = await _database.transaction((txn) async {
      final existing = await txn.query(
        'reminders',
        columns: ['updated_at'],
        where: 'id = ?',
        whereArgs: [id],
      );
      final localUpdated = existing.isEmpty
          ? null
          : existing.first['updated_at'] as int;
      if (localUpdated != null &&
          localUpdated >= updatedAt.millisecondsSinceEpoch) {
        return false;
      }
      if (deleted) {
        if (existing.isEmpty) return false;
        await txn.update(
          'reminders',
          {'deleted': 1, 'updated_at': updatedAt.millisecondsSinceEpoch},
          where: 'id = ?',
          whereArgs: [id],
        );
        return true;
      }
      if (reminder == null) return false;
      await txn.insert('reminders', {
        ..._reminderRow(reminder),
        'updated_at': updatedAt.millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return true;
    });
    if (changed) await _emitReminders();
    return changed;
  }

  /// Drops deletion markers once the backup no longer needs them.
  Future<void> purgeTombstones({
    Duration olderThan = const Duration(days: 60),
  }) {
    final cutoff = DateTime.now().subtract(olderThan).millisecondsSinceEpoch;
    return _database.delete(
      'reminders',
      where: 'deleted = 1 AND updated_at < ?',
      whereArgs: [cutoff],
    );
  }

  /// Re-reads everything and notifies listeners, e.g. on app resume, to pick
  /// up changes another isolate saved while the app was in the background.
  Future<void> reload() async {
    await _emitReminders();
    await _emitEvents();
  }

  /// Deletes all reminders and history on this device.
  Future<void> wipe() async {
    await _database.transaction((txn) async {
      await txn.delete('reminders');
      await txn.delete('events');
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

  Map<String, Object?> _reminderRow(ReminderModel reminder) => {
    'id': reminder.id,
    'data': jsonEncode(reminder.toJson()),
    'due_at': reminder.dueAt.millisecondsSinceEpoch,
    'updated_at': reminder.updatedAt.millisecondsSinceEpoch,
    'deleted': 0,
  };

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
          _reminderRow(r),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      for (final e in events) {
        batch.insert('events', {
          'id': e.id,
          'reminder_id': e.reminderId,
          'data': jsonEncode(e.toJson()),
          'occurred_at': e.occurredAt.millisecondsSinceEpoch,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      batch.insert('meta', {
        'key': _metaLegacyMigrated,
        'value': DateTime.now().toIso8601String(),
      });
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
