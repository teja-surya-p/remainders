import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'features.dart';
import 'insights/insights.dart';
import 'reminder_model.dart';
import 'reminder_sounds.dart';
import 'reminders/recurrence.dart';
import 'reminders/reminder_errors.dart';
import 'reminders/suggestions.dart';
import 'scheduling/alert_payload.dart';
import 'storage/reminder_backup.dart';
import 'storage/sqlite_reminder_store.dart';
import 'subscription_service.dart';

export 'insights/insights.dart'
    show
        ProductivityDayStats,
        ProductivityInsights,
        ReminderAnalytics,
        ReminderRiskStat,
        TimeSlotPerformance;
export 'reminders/reminder_errors.dart';

class ReminderService {
  final SubscriptionService subscription;

  ReminderService({
    required this.subscription,
    RemoteReminderBackup Function(String uid)? remoteBackup,
  }) : _remoteBackup =
           remoteBackup ?? ((uid) => FirestoreReminderBackup(uid: uid));

  final RemoteReminderBackup Function(String uid) _remoteBackup;

  final StreamController<List<ReminderModel>> _remindersController =
      StreamController<List<ReminderModel>>.broadcast();
  final StreamController<List<ReminderEvent>> _eventsController =
      StreamController<List<ReminderEvent>>.broadcast();

  StreamSubscription<List<ReminderModel>>? _activeReminderSub;
  StreamSubscription<List<ReminderEvent>>? _activeEventSub;

  /// The device's reminders (SQLite): the source of truth for everyone,
  /// signed in or not. The cloud is only a backup.
  SqliteReminderStore? _store;
  Future<void>? _initializing;

  /// Signed-in account, used only for backup. Null when signed out.
  User? _account;

  /// Backup of the device's reminders to the signed-in account.
  ReminderBackup? _backup;

  /// True while signed in, i.e. while the reminders are being backed up.
  final ValueNotifier<bool> backupOn = ValueNotifier<bool>(false);

  /// When the signed-in account was last synced on this phone; null when
  /// signed out or never.
  final ValueNotifier<DateTime?> lastBackupAt = ValueNotifier<DateTime?>(null);

  List<ReminderModel> _currentReminders = const [];
  List<ReminderEvent> _currentEvents = const [];

  /// Premium features (advanced repeats, auto-adjust, no daily limit, …).
  /// Everything is unlocked while the paywall is switched off (v1 is free).
  bool get isPremiumMode => !Features.paywall || subscription.isPremium;

  User? get account => _account;

  Stream<List<ReminderModel>> watchReminders() async* {
    yield List.unmodifiable(_currentReminders);
    yield* _remindersController.stream;
  }

  Stream<List<ReminderEvent>> watchEvents() async* {
    yield List.unmodifiable(_currentEvents);
    yield* _eventsController.stream;
  }

  List<ReminderModel> get currentReminders =>
      List.unmodifiable(_currentReminders);

  /// Opens the device database. Safe to call more than once and from any
  /// isolate: the app, the notification-action handler and the background
  /// re-arm job all call it, and none of them needs an account.
  Future<void> initialize({SqliteReminderStore? store}) =>
      _initializing ??= _initialize(store ?? SqliteReminderStore());

  Future<void> _initialize(SqliteReminderStore store) async {
    await store.initialize();
    _store = store;
    await _attachStreams();
  }

  /// Links the signed-in account for backup, or unlinks it (null) on
  /// sign-out. Reminders stay on the device either way.
  Future<void> attachAccount(User? user) async {
    if (user?.uid == _account?.uid) return;
    _account = user;
    _backup?.dispose();
    _backup = null;
    backupOn.value = false;
    lastBackupAt.value = null;
    if (user == null) return;

    await initialize();
    if (_account?.uid != user.uid) return; // changed again meanwhile
    final backup = ReminderBackup(
      uid: user.uid,
      local: _activeStoreOrThrow(),
      remote: _remoteBackup(user.uid),
    );
    _backup = backup;
    backupOn.value = true;
    lastBackupAt.value = await backup.lastSyncedAt();
    unawaited(syncBackup(force: true));
  }

  /// Downloads changes made on other devices and uploads this device's.
  /// Does nothing when signed out. Failures (e.g. offline) are only logged:
  /// the next sync tries again, and nothing on the device is lost.
  Future<BackupSyncResult?> syncBackup({bool force = false}) async {
    final backup = _backup;
    if (backup == null) return null;
    try {
      final result = await backup.syncNow(force: force);
      if (result != null) {
        debugPrint(
          'Backup synced: ${result.pulled} downloaded, '
          '${result.pushed} uploaded.',
        );
      }
      if (identical(backup, _backup)) {
        lastBackupAt.value = await backup.lastSyncedAt();
      }
      return result;
    } catch (e) {
      debugPrint('Backup sync failed: $e');
      return null;
    }
  }

  /// A full sync that also waits up to [timeout] for the server to confirm
  /// every upload. False if signed out, offline, or not all confirmed.
  Future<bool> backUpNow({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (await syncBackup(force: true) == null) return false;
    return flushBackup(timeout: timeout);
  }

  /// Sends changes not yet backed up and waits up to [timeout] for the
  /// server, e.g. before signing out. True when nothing is left only on
  /// this phone (always true when signed out: there is nowhere to send).
  Future<bool> flushBackup({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final backup = _backup;
    if (backup == null) return true;
    try {
      await backup.pushNow();
      await backup.uploadsSettled().timeout(timeout);
    } catch (e) {
      debugPrint('Backup not finished: $e');
    }
    final store = _activeStoreOrThrow();
    return (await store.listDirtyReminders()).isEmpty &&
        (await store.listDirtyEvents()).isEmpty;
  }

  /// Makes the next backup download and compare everything again.
  Future<void> forgetBackupState() async {
    await ReminderBackup.forget(_activeStoreOrThrow());
  }

  /// Deletes every reminder and all history on this phone (not the backup).
  Future<void> wipeDevice() async {
    await _activeStoreOrThrow().wipe();
  }

  Future<void> _attachStreams() async {
    await _activeReminderSub?.cancel();
    await _activeEventSub?.cancel();

    final store = _activeStoreOrThrow();

    _activeReminderSub = store.watchReminders().listen((items) {
      _currentReminders = List.unmodifiable(items);
      if (!_remindersController.isClosed) {
        _remindersController.add(_currentReminders);
      }
    });

    _activeEventSub = store.watchEvents().listen((items) {
      _currentEvents = List.unmodifiable(items);
      if (!_eventsController.isClosed) {
        _eventsController.add(_currentEvents);
      }
    });

    _currentReminders = await store.listReminders();
    _currentEvents = await store.listEvents();

    if (!_remindersController.isClosed) {
      _remindersController.add(_currentReminders);
    }
    if (!_eventsController.isClosed) {
      _eventsController.add(_currentEvents);
    }
  }

  Future<void> dispose() async {
    _backup?.dispose();
    _backup = null;
    await _activeReminderSub?.cancel();
    await _activeEventSub?.cancel();
    await _store?.dispose();
    _store = null;
    _initializing = null;
    await _remindersController.close();
    await _eventsController.close();
  }

  Future<int> countActiveRemindersForDay(
    DateTime day, {
    String? excludingId,
  }) async {
    final reminders = await _activeStoreOrThrow().listReminders();
    final date = dayOnly(day);
    var count = 0;
    for (final reminder in reminders) {
      if (excludingId != null && reminder.id == excludingId) continue;
      if (!reminder.isActive) continue;
      if (dayOnly(reminder.dueAt) == date) count += 1;
    }
    return count;
  }

  /// Picks up changes another isolate saved while the app was in the
  /// background (see SqliteReminderStore.reload), then syncs the backup.
  Future<void> reloadLocal() async {
    await _store?.reload();
    unawaited(syncBackup());
  }

  Future<List<ReminderModel>> listReminders() async {
    return _activeStoreOrThrow().listReminders();
  }

  Future<ReminderModel?> getReminder(String id) async {
    return _activeStoreOrThrow().getReminder(id);
  }

  Future<ReminderModel> createReminder({
    required String title,
    String? description,
    required DateTime dueAt,
    ReminderRecurrence? recurrence,
    ReminderAlertMode alertMode = ReminderAlertMode.ringAndNotify,
    ReminderPriority priority = ReminderPriority.medium,
    String? alarmSoundId,
    String? notificationSoundId,
  }) async {
    final trimmedTitle = title.trim();
    if (trimmedTitle.isEmpty) {
      throw const ReminderValidationException('Reminder name is required.');
    }

    final normalizedRecurrence = _normalizeRecurrence(
      recurrence ?? ReminderRecurrence(),
      dueAt,
    );
    _validateRecurrenceOrThrow(normalizedRecurrence);

    await _enforceFreeReminderLimitOrThrow(dueAt);

    final now = DateTime.now();
    final id = generateReminderId();
    final nextDue = resolveInitialDue(
      dueAt,
      normalizedRecurrence,
      reference: now,
    );

    if (nextDue == null) {
      throw const ReminderValidationException(
        'No valid occurrence could be generated for this recurrence.',
      );
    }

    final reminder = ReminderModel(
      id: id,
      title: trimmedTitle,
      description: description?.trim().isEmpty == true
          ? null
          : description?.trim(),
      dueAt: nextDue,
      recurrence: normalizedRecurrence,
      alertMode: alertMode,
      priority: priority,
      alarmSoundId: alarmSoundId ?? ReminderSounds.defaultAlarmSoundId,
      notificationSoundId:
          notificationSoundId ?? ReminderSounds.defaultNotificationSoundId,
      createdAt: now,
      updatedAt: now,
      totalOccurrences: 0,
      completionCount: 0,
      missedCount: 0,
      currentStreak: 0,
      longestStreak: 0,
      recoveryUsedCount: 0,
      streakBeforeMiss: 0,
    );

    await _writeReminder(reminder);
    return reminder;
  }

  Future<ReminderModel> updateReminder(ReminderModel reminder) async {
    final title = reminder.title.trim();
    if (title.isEmpty) {
      throw const ReminderValidationException('Reminder name is required.');
    }

    final normalizedRecurrence = _normalizeRecurrence(
      reminder.recurrence,
      reminder.dueAt,
    );
    _validateRecurrenceOrThrow(normalizedRecurrence);
    await _enforceFreeReminderLimitOrThrow(
      reminder.dueAt,
      editingId: reminder.id,
    );

    final now = DateTime.now();
    final nextDue = resolveInitialDue(
      reminder.dueAt,
      normalizedRecurrence,
      reference: now,
    );

    if (nextDue == null) {
      throw const ReminderValidationException(
        'No valid occurrence could be generated for this recurrence.',
      );
    }

    final updated = reminder.copyWith(
      title: title,
      dueAt: nextDue,
      recurrence: normalizedRecurrence,
      completed: false,
      missed: false,
      updatedAt: now,
      clearNotifIdMain: true,
      clearNotifIdPre: true,
    );

    await _writeReminder(updated);
    return updated;
  }

  Future<void> deleteReminder(String id) async {
    await _activeStoreOrThrow().deleteReminder(id);
    _backup?.schedulePush();
  }

  /// [expectedDueAt] is the occurrence the user is answering (from the alarm
  /// payload). If the reminder already moved past it — the same alarm
  /// answered twice, e.g. from the notification and the alarm screen — the
  /// call does nothing.
  Future<void> snoozeReminder(
    String reminderId,
    DateTime newDueAt, {
    String? platform,
    DateTime? expectedDueAt,
  }) async {
    final reminder = await _activeStoreOrThrow().getReminder(reminderId);
    if (reminder == null) return;
    if (_alreadyAnswered(reminder, expectedDueAt)) return;

    final now = DateTime.now();
    final snoozeMinutes = newDueAt.difference(now).inMinutes;
    final updated = reminder.copyWith(
      dueAt: newDueAt,
      completed: false,
      missed: false,
      consecutiveSnoozes: reminder.consecutiveSnoozes + 1,
      updatedAt: now,
      lastOccurrenceStatus: 'snoozed',
      lastOccurrenceAt: reminder.dueAt,
      clearNotifIdMain: true,
      clearNotifIdPre: true,
    );

    await _writeReminder(updated);

    await _writeEvent(
      ReminderEvent(
        id: generateReminderId(),
        reminderId: reminderId,
        type: ReminderEventType.snoozed,
        scheduledAt: reminder.dueAt,
        occurredAt: now,
        snoozeMinutes: snoozeMinutes < 0 ? 0 : snoozeMinutes,
      ),
    );

    await _recomputeSuggestion(reminderId);
  }

  Future<void> dismissReminder(
    String reminderId, {
    DateTime? expectedDueAt,
  }) async {
    await completeReminder(reminderId, expectedDueAt: expectedDueAt);
  }

  /// See [snoozeReminder] for [expectedDueAt].
  Future<void> completeReminder(
    String reminderId, {
    DateTime? expectedDueAt,
  }) async {
    final reminder = await _activeStoreOrThrow().getReminder(reminderId);
    if (reminder == null) return;
    if (_alreadyAnswered(reminder, expectedDueAt)) return;

    final now = DateTime.now();
    final scheduledAt = reminder.dueAt;

    final wasConsecutive = isConsecutiveScheduledOccurrence(
      reminder,
      scheduledAt,
    );
    final nextStreak = wasConsecutive ? reminder.currentStreak + 1 : 1;

    ReminderModel updated = reminder.copyWith(
      completionCount: reminder.completionCount + 1,
      totalOccurrences: reminder.totalOccurrences + 1,
      currentStreak: nextStreak,
      longestStreak: nextStreak > reminder.longestStreak
          ? nextStreak
          : reminder.longestStreak,
      lastCompletedAt: now,
      lastOccurrenceAt: scheduledAt,
      lastOccurrenceStatus: 'completed',
      consecutiveSnoozes: 0,
      streakBeforeMiss: 0,
      updatedAt: now,
      clearSuggestionMessage: true,
      clearSuggestionCreatedAt: true,
      clearSuggestionMinutesOfDay: true,
    );

    if (updated.recurrence.isRepeating) {
      final next = nextRecurringDue(
        from: now.add(const Duration(seconds: 1)),
        recurrence: updated.recurrence,
        anchor: scheduledAt,
      );

      if (next == null) {
        updated = updated.copyWith(
          completed: true,
          missed: false,
          clearNotifIdMain: true,
          clearNotifIdPre: true,
        );
      } else {
        updated = updated.copyWith(
          dueAt: next,
          completed: false,
          missed: false,
          clearNotifIdMain: true,
          clearNotifIdPre: true,
        );
      }
    } else {
      updated = updated.copyWith(
        completed: true,
        missed: false,
        clearNotifIdMain: true,
        clearNotifIdPre: true,
      );
    }

    await _writeReminder(updated);

    await _writeEvent(
      ReminderEvent(
        id: generateReminderId(),
        reminderId: reminderId,
        type: ReminderEventType.completed,
        scheduledAt: scheduledAt,
        occurredAt: now,
      ),
    );

    await _recomputeSuggestion(reminderId);
  }

  Future<void> markReminderMissedOrAdvance(String reminderId) async {
    final reminder = await _activeStoreOrThrow().getReminder(reminderId);
    if (reminder == null) return;
    final now = DateTime.now();

    if (!reminder.dueAt.isBefore(now.subtract(const Duration(seconds: 5)))) {
      return;
    }

    final scheduledAt = reminder.dueAt;
    ReminderModel updated = reminder.copyWith(
      missedCount: reminder.missedCount + 1,
      totalOccurrences: reminder.totalOccurrences + 1,
      currentStreak: 0,
      streakBeforeMiss: reminder.currentStreak,
      consecutiveSnoozes: 0,
      lastOccurrenceAt: scheduledAt,
      lastOccurrenceStatus: 'missed',
      updatedAt: now,
      clearNotifIdMain: true,
      clearNotifIdPre: true,
    );

    if (updated.recurrence.isRepeating) {
      final next = nextRecurringDue(
        from: now.add(const Duration(seconds: 1)),
        recurrence: updated.recurrence,
        anchor: scheduledAt,
      );
      if (next == null) {
        updated = updated.copyWith(completed: true, missed: true);
      } else {
        updated = updated.copyWith(
          dueAt: next,
          completed: false,
          missed: false,
        );
      }
    } else {
      updated = updated.copyWith(completed: true, missed: true);
    }

    await _writeReminder(updated);

    await _writeEvent(
      ReminderEvent(
        // One per occurrence: if the app and its background job both record
        // the same miss, the second write replaces the first.
        id: 'missed_${reminderId}_${epochMinute(scheduledAt)}',
        reminderId: reminderId,
        type: ReminderEventType.missed,
        scheduledAt: scheduledAt,
        occurredAt: now,
      ),
    );

    await _recomputeSuggestion(reminderId);
  }

  Future<void> recoverStreak(String reminderId) async {
    if (!isPremiumMode) {
      throw const PremiumRequiredException(
        feature: 'streak_recovery',
        message: 'Premium required for streak recovery.',
      );
    }

    final reminder = await _activeStoreOrThrow().getReminder(reminderId);
    if (reminder == null) return;

    final now = DateTime.now();
    final lastRecoveryAt = reminder.lastRecoveryAt;
    if (lastRecoveryAt != null &&
        now.difference(lastRecoveryAt) < const Duration(days: 30)) {
      throw const ReminderValidationException(
        'Streak recovery is available once every 30 days.',
      );
    }

    final recoveredStreak = reminder.streakBeforeMiss > 0
        ? reminder.streakBeforeMiss
        : 1;
    final updated = reminder.copyWith(
      currentStreak: recoveredStreak,
      longestStreak: recoveredStreak > reminder.longestStreak
          ? recoveredStreak
          : reminder.longestStreak,
      recoveryUsedCount: reminder.recoveryUsedCount + 1,
      lastRecoveryAt: now,
      updatedAt: now,
    );

    await _writeReminder(updated);
  }

  Future<void> applySuggestion(String reminderId) async {
    if (!isPremiumMode) {
      throw const PremiumRequiredException(
        feature: 'smart_scheduling',
        message: 'Premium required to auto-adjust schedules.',
      );
    }

    final reminder = await _activeStoreOrThrow().getReminder(reminderId);
    if (reminder == null) return;

    final suggested = reminder.suggestionMinutesOfDay;
    if (suggested == null) return;

    final times = reminder.recurrence.timesOfDay.isEmpty
        ? <int>[suggested]
        : <int>[suggested, ...reminder.recurrence.timesOfDay.skip(1)];

    final updatedRecurrence = reminder.recurrence.copyWith(timesOfDay: times);

    final nextDue = reminder.recurrence.isRepeating
        ? nextRecurringDue(
            from: DateTime.now().add(const Duration(seconds: 1)),
            recurrence: updatedRecurrence,
            anchor: reminder.dueAt,
          )
        : dateWithMinutes(DateTime.now(), suggested);

    final updated = reminder.copyWith(
      recurrence: updatedRecurrence,
      dueAt: nextDue ?? reminder.dueAt,
      updatedAt: DateTime.now(),
      clearSuggestionMessage: true,
      clearSuggestionCreatedAt: true,
      clearSuggestionMinutesOfDay: true,
      clearNotifIdMain: true,
      clearNotifIdPre: true,
    );

    await _writeReminder(updated);
  }

  Future<ReminderAnalytics> computeAnalytics() async {
    final store = _activeStoreOrThrow();
    return buildAnalytics(
      reminders: await store.listReminders(),
      events: await store.listEvents(),
    );
  }

  Future<ProductivityInsights> computeProductivityInsights({
    int contributionDays = 84,
  }) async {
    final store = _activeStoreOrThrow();
    return buildProductivityInsights(
      reminders: await store.listReminders(),
      events: await store.listEvents(),
      contributionDays: contributionDays,
    );
  }

  Future<void> _recomputeSuggestion(String reminderId) async {
    final store = _activeStoreOrThrow();
    final reminder = await store.getReminder(reminderId);
    if (reminder == null) return;
    final now = DateTime.now();
    final suggestion = suggestTime(
      reminder,
      await store.listEvents(),
      now: now,
    );
    await _writeReminder(
      reminder.copyWith(
        suggestionMinutesOfDay: suggestion?.minuteOfDay,
        suggestionMessage: suggestion?.message,
        suggestionCreatedAt: suggestion == null ? null : now,
        clearSuggestionMinutesOfDay: suggestion == null,
        clearSuggestionMessage: suggestion == null,
        clearSuggestionCreatedAt: suggestion == null,
        updatedAt: now,
      ),
    );
  }

  Future<void> _writeReminder(ReminderModel reminder) async {
    await _activeStoreOrThrow().upsertReminder(reminder);
    _backup?.schedulePush();
  }

  Future<void> _writeEvent(ReminderEvent event) async {
    await _activeStoreOrThrow().upsertEvent(event);
    _backup?.schedulePush();
  }

  bool _alreadyAnswered(ReminderModel reminder, DateTime? expectedDueAt) {
    if (expectedDueAt == null) return false;
    return !reminder.isActive || !sameMinute(reminder.dueAt, expectedDueAt);
  }

  SqliteReminderStore _activeStoreOrThrow() {
    final store = _store;
    if (store == null) {
      throw StateError('Reminders are not ready yet.');
    }
    return store;
  }

  Future<void> _enforceFreeReminderLimitOrThrow(
    DateTime dueAt, {
    String? editingId,
  }) async {
    if (isPremiumMode) return;

    final count = await countActiveRemindersForDay(
      dueAt,
      excludingId: editingId,
    );
    if (count >= 5) {
      throw const PremiumRequiredException(
        feature: 'unlimited_reminders',
        message:
            'Free plan allows up to 5 active reminders per day. Upgrade to Premium to add more.',
      );
    }
  }

  ReminderRecurrence _normalizeRecurrence(
    ReminderRecurrence recurrence,
    DateTime dueAt,
  ) {
    if (recurrence.type == RepeatType.none) {
      return ReminderRecurrence();
    }

    final times =
        (recurrence.timesOfDay.isEmpty
                ? <int>[minutesOfDay(dueAt)]
                : recurrence.timesOfDay)
            .where((m) => m >= 0 && m <= 1439)
            .toSet()
            .toList()
          ..sort();

    final weekdays =
        recurrence.weekdays.where((d) => d >= 1 && d <= 7).toSet().toList()
          ..sort();

    if (recurrence.type == RepeatType.daily) {
      return recurrence.copyWith(weekdays: const [], timesOfDay: times);
    }

    if (recurrence.type == RepeatType.weekly) {
      final resolved = weekdays.isEmpty ? <int>[dueAt.weekday] : weekdays;
      return recurrence.copyWith(weekdays: resolved, timesOfDay: times);
    }

    if (recurrence.type == RepeatType.interval) {
      final interval = recurrence.intervalDays ?? 1;
      return recurrence.copyWith(
        intervalDays: interval <= 0 ? 1 : interval,
        weekdays: const [],
        timesOfDay: times,
      );
    }

    return recurrence;
  }

  void _validateRecurrenceOrThrow(ReminderRecurrence recurrence) {
    if (recurrence.type == RepeatType.none) return;

    if (recurrence.timesOfDay.isEmpty) {
      throw const ReminderValidationException('At least one time is required.');
    }

    if (!isPremiumMode) {
      final freeAllowed =
          recurrence.type == RepeatType.daily ||
          recurrence.type == RepeatType.weekly;
      if (!freeAllowed) {
        throw const PremiumRequiredException(
          feature: 'advanced_recurrence',
          message: 'Advanced recurrence requires Premium.',
        );
      }
      if (recurrence.type == RepeatType.weekly &&
          recurrence.weekdays.length > 1) {
        throw const PremiumRequiredException(
          feature: 'advanced_recurrence',
          message: 'Custom weekday combinations require Premium.',
        );
      }
      if (recurrence.timesOfDay.length > 1) {
        throw const PremiumRequiredException(
          feature: 'advanced_recurrence',
          message: 'Multiple reminders per day require Premium.',
        );
      }
      if (recurrence.endAt != null) {
        throw const PremiumRequiredException(
          feature: 'advanced_recurrence',
          message: 'Date-range recurrence requires Premium.',
        );
      }
    }

    if (recurrence.type == RepeatType.weekly && recurrence.weekdays.isEmpty) {
      throw const ReminderValidationException(
        'Select at least one weekday for weekly recurrence.',
      );
    }

    if (recurrence.type == RepeatType.interval) {
      final interval = recurrence.intervalDays ?? 0;
      if (interval <= 0) {
        throw const ReminderValidationException(
          'Interval recurrence must have a positive interval.',
        );
      }
    }
  }
}
