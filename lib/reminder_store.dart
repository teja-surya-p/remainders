import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'reminder_model.dart';

abstract class ReminderStore {
  Future<void> initialize();

  Stream<List<ReminderModel>> watchReminders();
  Future<List<ReminderModel>> listReminders();
  Future<ReminderModel?> getReminder(String id);
  Future<void> upsertReminder(ReminderModel reminder);
  Future<void> upsertReminders(List<ReminderModel> reminders);
  Future<void> deleteReminder(String id);

  Stream<List<ReminderEvent>> watchEvents();
  Future<List<ReminderEvent>> listEvents();
  Future<void> upsertEvent(ReminderEvent event);
  Future<void> upsertEvents(List<ReminderEvent> events);

  Future<void> dispose();
}

class LocalReminderStore implements ReminderStore {
  final String uid;

  LocalReminderStore({required this.uid});

  static const String _kReminderPrefix = 'local_reminders_';
  static const String _kEventsPrefix = 'local_reminder_events_';

  SharedPreferences? _prefs;
  final List<ReminderModel> _reminders = [];
  final List<ReminderEvent> _events = [];

  final StreamController<List<ReminderModel>> _remindersController =
      StreamController<List<ReminderModel>>.broadcast();
  final StreamController<List<ReminderEvent>> _eventsController =
      StreamController<List<ReminderEvent>>.broadcast();

  String get _reminderKey => '$_kReminderPrefix$uid';
  String get _eventsKey => '$_kEventsPrefix$uid';

  @override
  Future<void> initialize() async {
    _prefs ??= await SharedPreferences.getInstance();
    _reminders
      ..clear()
      ..addAll(_readReminders());
    _events
      ..clear()
      ..addAll(_readEvents());
    _emit();
  }

  @override
  Stream<List<ReminderModel>> watchReminders() {
    return _remindersController.stream;
  }

  @override
  Future<List<ReminderModel>> listReminders() async {
    return List.unmodifiable(_reminders);
  }

  @override
  Future<ReminderModel?> getReminder(String id) async {
    for (final reminder in _reminders) {
      if (reminder.id == id) return reminder;
    }
    return null;
  }

  @override
  Future<void> upsertReminder(ReminderModel reminder) async {
    await _refreshFromDisk();
    final index = _reminders.indexWhere((r) => r.id == reminder.id);
    if (index >= 0) {
      _reminders[index] = reminder;
    } else {
      _reminders.add(reminder);
    }
    _sortReminders();
    await _persistReminders();
    _emitReminders();
  }

  @override
  Future<void> upsertReminders(List<ReminderModel> reminders) async {
    await _refreshFromDisk();
    final map = {for (final r in _reminders) r.id: r};
    for (final reminder in reminders) {
      map[reminder.id] = reminder;
    }
    _reminders
      ..clear()
      ..addAll(map.values);
    _sortReminders();
    await _persistReminders();
    _emitReminders();
  }

  @override
  Future<void> deleteReminder(String id) async {
    await _refreshFromDisk();
    _reminders.removeWhere((r) => r.id == id);
    await _persistReminders();
    _emitReminders();
  }

  @override
  Stream<List<ReminderEvent>> watchEvents() {
    return _eventsController.stream;
  }

  @override
  Future<List<ReminderEvent>> listEvents() async {
    return List.unmodifiable(_events);
  }

  @override
  Future<void> upsertEvent(ReminderEvent event) async {
    await _refreshFromDisk();
    final index = _events.indexWhere((e) => e.id == event.id);
    if (index >= 0) {
      _events[index] = event;
    } else {
      _events.add(event);
    }
    _sortEvents();
    await _persistEvents();
    _emitEvents();
  }

  @override
  Future<void> upsertEvents(List<ReminderEvent> events) async {
    await _refreshFromDisk();
    final map = {for (final e in _events) e.id: e};
    for (final event in events) {
      map[event.id] = event;
    }
    _events
      ..clear()
      ..addAll(map.values);
    _sortEvents();
    await _persistEvents();
    _emitEvents();
  }

  /// Re-reads saved data (e.g. on app resume) so changes made by another
  /// isolate — a snooze from the notification while the app was in the
  /// background — show up, then notifies listeners.
  Future<void> reload() async {
    await _refreshFromDisk();
    _emit();
  }

  /// The notification-action background isolate keeps its own copy of the
  /// data. Every write re-reads the latest saved state first, so one
  /// isolate's copy never overwrites the other's changes. Both isolates run in
  /// the same Android process, so `reload()` sees each other's writes at once.
  Future<void> _refreshFromDisk() async {
    final prefs = _prefs;
    if (prefs == null) return;
    await prefs.reload();
    _reminders
      ..clear()
      ..addAll(_readReminders());
    _events
      ..clear()
      ..addAll(_readEvents());
    _sortReminders();
    _sortEvents();
  }

  @override
  Future<void> dispose() async {
    await _remindersController.close();
    await _eventsController.close();
  }

  void _sortReminders() {
    _reminders.sort((a, b) => a.dueAt.compareTo(b.dueAt));
  }

  void _sortEvents() {
    _events.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
  }

  List<ReminderModel> _readReminders() {
    final prefs = _prefs;
    if (prefs == null) return const [];
    final raw = prefs.getString(_reminderKey);
    if (raw == null || raw.isEmpty) return const [];

    return _decodeList(
      raw,
      _reminderKey,
      ReminderModel.fromJson,
    ).where((r) => r.id.isNotEmpty).toList();
  }

  List<ReminderEvent> _readEvents() {
    final prefs = _prefs;
    if (prefs == null) return const [];
    final raw = prefs.getString(_eventsKey);
    if (raw == null || raw.isEmpty) return const [];

    return _decodeList(
      raw,
      _eventsKey,
      ReminderEvent.fromJson,
    ).where((e) => e.id.isNotEmpty).toList();
  }

  /// Decodes a saved list item by item. An unreadable item is skipped instead
  /// of losing the whole list; if anything was unreadable, the raw value is
  /// copied to a backup key first so the next save can't destroy it.
  List<T> _decodeList<T>(
    String raw,
    String key,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    List<dynamic> items;
    try {
      items = jsonDecode(raw) as List<dynamic>;
    } catch (e) {
      _backupCorrupt(key, raw, e);
      return <T>[];
    }
    final out = <T>[];
    var failed = false;
    for (final item in items) {
      try {
        out.add(fromJson(Map<String, dynamic>.from(item as Map)));
      } catch (e) {
        failed = true;
        debugPrint('Skipping unreadable saved item in $key: $e');
      }
    }
    if (failed) _backupCorrupt(key, raw, 'unreadable items');
    return out;
  }

  void _backupCorrupt(String key, String raw, Object reason) {
    final prefs = _prefs;
    if (prefs == null) return;
    final backupKey = '${key}_unreadable_backup';
    if (prefs.containsKey(backupKey)) return;
    debugPrint(
      'Saved data in $key could not be fully read ($reason); kept a backup.',
    );
    unawaited(prefs.setString(backupKey, raw));
  }

  Future<void> _persistReminders() async {
    final prefs = _prefs;
    if (prefs == null) return;
    final list = _reminders.map((e) => e.toJson()).toList(growable: false);
    await prefs.setString(_reminderKey, jsonEncode(list));
  }

  Future<void> _persistEvents() async {
    final prefs = _prefs;
    if (prefs == null) return;
    final list = _events.map((e) => e.toJson()).toList(growable: false);
    await prefs.setString(_eventsKey, jsonEncode(list));
  }

  void _emit() {
    _emitReminders();
    _emitEvents();
  }

  void _emitReminders() {
    if (_remindersController.isClosed) return;
    _remindersController.add(List.unmodifiable(_reminders));
  }

  void _emitEvents() {
    if (_eventsController.isClosed) return;
    _eventsController.add(List.unmodifiable(_events));
  }
}

class CloudReminderStore implements ReminderStore {
  final String uid;
  final FirebaseFirestore firestore;

  CloudReminderStore({required this.uid, FirebaseFirestore? firestore})
    : firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _remindersRef =>
      firestore.collection('users/$uid/reminders');

  CollectionReference<Map<String, dynamic>> get _eventsRef =>
      firestore.collection('users/$uid/reminderEvents');

  DocumentReference<Map<String, dynamic>> get _userRef =>
      firestore.doc('users/$uid');

  @override
  Future<void> initialize() async {
    // Refresh the profile doc without waiting: Firestore write futures only
    // complete once the server confirms, so awaiting this made every launch
    // (and every background alarm action) hang while offline. `createdAt` is
    // no longer rewritten on every sign-in.
    unawaited(
      _userRef
          .set({
            'uid': uid,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true))
          .catchError((Object e) {
            debugPrint('Profile write failed: $e');
          }),
    );
  }

  @override
  Stream<List<ReminderModel>> watchReminders() {
    return _remindersRef.orderBy('dueAt').snapshots().map((snap) {
      return snap.docs
          .map((doc) => ReminderModel.fromCloudDoc(doc.id, doc.data()))
          .toList(growable: false);
    });
  }

  @override
  Future<List<ReminderModel>> listReminders() async {
    final snap = await _remindersRef.orderBy('dueAt').get();
    return snap.docs
        .map((doc) => ReminderModel.fromCloudDoc(doc.id, doc.data()))
        .toList(growable: false);
  }

  @override
  Future<ReminderModel?> getReminder(String id) async {
    final doc = await _remindersRef.doc(id).get();
    final data = doc.data();
    if (data == null) return null;
    return ReminderModel.fromCloudDoc(doc.id, data);
  }

  @override
  Future<void> upsertReminder(ReminderModel reminder) async {
    await _remindersRef.doc(reminder.id).set(reminder.toCloudMap());
    await _touchUser();
  }

  @override
  Future<void> upsertReminders(List<ReminderModel> reminders) async {
    if (reminders.isEmpty) return;
    final batch = firestore.batch();
    for (final reminder in reminders) {
      batch.set(_remindersRef.doc(reminder.id), reminder.toCloudMap());
    }
    await batch.commit();
    await _touchUser();
  }

  @override
  Future<void> deleteReminder(String id) async {
    await _remindersRef.doc(id).delete();
  }

  @override
  Stream<List<ReminderEvent>> watchEvents() {
    return _eventsRef.orderBy('occurredAt', descending: true).snapshots().map((
      snap,
    ) {
      return snap.docs
          .map((doc) => ReminderEvent.fromCloudDoc(doc.id, doc.data()))
          .toList(growable: false);
    });
  }

  @override
  Future<List<ReminderEvent>> listEvents() async {
    final snap = await _eventsRef.orderBy('occurredAt', descending: true).get();
    return snap.docs
        .map((doc) => ReminderEvent.fromCloudDoc(doc.id, doc.data()))
        .toList(growable: false);
  }

  @override
  Future<void> upsertEvent(ReminderEvent event) async {
    await _eventsRef.doc(event.id).set(event.toCloudMap());
    await _touchUser();
  }

  @override
  Future<void> upsertEvents(List<ReminderEvent> events) async {
    if (events.isEmpty) return;
    final batch = firestore.batch();
    for (final event in events) {
      batch.set(_eventsRef.doc(event.id), event.toCloudMap());
    }
    await batch.commit();
    await _touchUser();
  }

  @override
  Future<void> dispose() async {}

  Future<void> _touchUser() async {
    await _userRef.set({
      'uid': uid,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
