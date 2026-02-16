import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

import 'reminder_model.dart';
import 'reminder_sounds.dart';
import 'reminder_store.dart';
import 'repeat_utils.dart';
import 'subscription_service.dart';

class PremiumRequiredException implements Exception {
  final String feature;
  final String message;

  const PremiumRequiredException({
    required this.feature,
    required this.message,
  });

  @override
  String toString() => message;
}

class ReminderValidationException implements Exception {
  final String message;

  const ReminderValidationException(this.message);

  @override
  String toString() => message;
}

class ReminderAnalytics {
  final double weeklyCompletionRate;
  final double monthlyCompletionRate;
  final String? mostMissedReminderId;
  final Map<String, double> timeOfDayPerformance;
  final int longestStreak;

  const ReminderAnalytics({
    required this.weeklyCompletionRate,
    required this.monthlyCompletionRate,
    required this.mostMissedReminderId,
    required this.timeOfDayPerformance,
    required this.longestStreak,
  });
}

class TimeSlotPerformance {
  final String label;
  final int completed;
  final int total;

  const TimeSlotPerformance({
    required this.label,
    required this.completed,
    required this.total,
  });

  double get rate => total == 0 ? 0 : completed / total;
}

class ReminderRiskStat {
  final String reminderId;
  final int completedCount;
  final int missedCount;
  final int snoozedCount;

  const ReminderRiskStat({
    required this.reminderId,
    required this.completedCount,
    required this.missedCount,
    required this.snoozedCount,
  });

  int get trackedCount => completedCount + missedCount;
  double get completionRate =>
      trackedCount == 0 ? 0 : completedCount / trackedCount;
  int get riskScore => (missedCount * 2) + snoozedCount;
}

class ProductivityDayStats {
  final DateTime day;
  final int completed;
  final int missed;
  final int snoozed;

  const ProductivityDayStats({
    required this.day,
    required this.completed,
    required this.missed,
    required this.snoozed,
  });

  int get trackedCount => completed + missed;
  double get completionRate => trackedCount == 0 ? 0 : completed / trackedCount;
}

class ProductivityInsights {
  final ReminderAnalytics summary;
  final int productivityScore;
  final int currentDayStreak;
  final int bestDayStreak;
  final int completedToday;
  final int missedToday;
  final int snoozedToday;
  final int dueToday;
  final int pendingToday;
  final double weeklySnoozePerCompletion;
  final String? bestFocusLabel;
  final List<TimeSlotPerformance> slotPerformance;
  final List<ProductivityDayStats> contributionDays;
  final List<ProductivityDayStats> recentDays;
  final List<ReminderRiskStat> atRiskReminders;
  final List<ReminderRiskStat> topPerformers;

  const ProductivityInsights({
    required this.summary,
    required this.productivityScore,
    required this.currentDayStreak,
    required this.bestDayStreak,
    required this.completedToday,
    required this.missedToday,
    required this.snoozedToday,
    required this.dueToday,
    required this.pendingToday,
    required this.weeklySnoozePerCompletion,
    required this.bestFocusLabel,
    required this.slotPerformance,
    required this.contributionDays,
    required this.recentDays,
    required this.atRiskReminders,
    required this.topPerformers,
  });
}

class ReminderService {
  final SubscriptionService subscription;

  ReminderService({required this.subscription});

  final StreamController<List<ReminderModel>> _remindersController =
      StreamController<List<ReminderModel>>.broadcast();
  final StreamController<List<ReminderEvent>> _eventsController =
      StreamController<List<ReminderEvent>>.broadcast();

  StreamSubscription<List<ReminderModel>>? _activeReminderSub;
  StreamSubscription<List<ReminderEvent>>? _activeEventSub;
  bool _listeningSubscription = false;

  LocalReminderStore? _local;
  CloudReminderStore? _cloud;
  User? _user;

  List<ReminderModel> _currentReminders = const [];
  List<ReminderEvent> _currentEvents = const [];

  bool _modePremium = false;
  bool _cloudSyncEnabled = false;

  bool get isPremiumMode => _modePremium;

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

  Future<void> bindUser(User user) async {
    _user = user;

    await _activeReminderSub?.cancel();
    await _activeEventSub?.cancel();
    await _local?.dispose();
    await _cloud?.dispose();

    _local = LocalReminderStore(uid: user.uid);
    _cloud = CloudReminderStore(uid: user.uid);
    await _local!.initialize();
    await _cloud!.initialize();

    _modePremium = subscription.isPremium;
    _cloudSyncEnabled = subscription.shouldUseCloudSync;

    if (_cloudSyncEnabled) {
      // Merge local history into cloud on sign-in if premium is already active.
      await _syncLocalToCloud();
      // Keep device cache aligned with cloud after upload.
      await _syncCloudToLocal();
    }

    await _attachActiveStreams();

    if (!_listeningSubscription) {
      subscription.state.addListener(_onSubscriptionChanged);
      _listeningSubscription = true;
    }
  }

  void _onSubscriptionChanged() {
    unawaited(_handleModeTransition());
  }

  Future<void> _handleModeTransition() async {
    if (_user == null) return;
    final shouldBePremium = subscription.isPremium;
    final shouldUseCloud = subscription.shouldUseCloudSync;

    final premiumChanged = shouldBePremium != _modePremium;
    final cloudChanged = shouldUseCloud != _cloudSyncEnabled;

    if (!premiumChanged && !cloudChanged) return;

    if (cloudChanged) {
      if (shouldUseCloud) {
        await _syncLocalToCloud();
      } else {
        await _syncCloudToLocal();
      }
      _cloudSyncEnabled = shouldUseCloud;
      await _attachActiveStreams();
    }

    _modePremium = shouldBePremium;
  }

  Future<void> _attachActiveStreams() async {
    await _activeReminderSub?.cancel();
    await _activeEventSub?.cancel();

    final active = _activeStoreOrThrow();

    _activeReminderSub = active.watchReminders().listen((items) {
      _currentReminders = List.unmodifiable(items);
      if (!_remindersController.isClosed) {
        _remindersController.add(_currentReminders);
      }
    });

    _activeEventSub = active.watchEvents().listen((items) {
      _currentEvents = List.unmodifiable(items);
      if (!_eventsController.isClosed) {
        _eventsController.add(_currentEvents);
      }
    });

    _currentReminders = await active.listReminders();
    _currentEvents = await active.listEvents();

    if (!_remindersController.isClosed) {
      _remindersController.add(_currentReminders);
    }
    if (!_eventsController.isClosed) {
      _eventsController.add(_currentEvents);
    }
  }

  Future<void> unbindUser() async {
    _user = null;
    await _activeReminderSub?.cancel();
    await _activeEventSub?.cancel();
    _activeReminderSub = null;
    _activeEventSub = null;
    _currentReminders = const [];
    _currentEvents = const [];
    _modePremium = false;
    _cloudSyncEnabled = false;

    await _local?.dispose();
    await _cloud?.dispose();
    _local = null;
    _cloud = null;

    if (_listeningSubscription) {
      subscription.state.removeListener(_onSubscriptionChanged);
      _listeningSubscription = false;
    }
  }

  Future<void> dispose() async {
    await unbindUser();
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
    _requireSignedIn();

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
    final nextDue = _resolveInitialDue(
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
    _requireSignedIn();
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
    final nextDue = _resolveInitialDue(
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
    _requireSignedIn();
    await _activeStoreOrThrow().deleteReminder(id);

    if (_modePremium) {
      await _local?.deleteReminder(id);
    }
  }

  Future<void> snoozeReminder(
    String reminderId,
    DateTime newDueAt, {
    String? platform,
  }) async {
    _requireSignedIn();

    final reminder = await _activeStoreOrThrow().getReminder(reminderId);
    if (reminder == null) return;

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

  Future<void> dismissReminder(String reminderId) async {
    await completeReminder(reminderId);
  }

  Future<void> completeReminder(String reminderId) async {
    _requireSignedIn();

    final reminder = await _activeStoreOrThrow().getReminder(reminderId);
    if (reminder == null) return;

    final now = DateTime.now();
    final scheduledAt = reminder.dueAt;

    final wasConsecutive = _isConsecutiveScheduledOccurrence(
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
      final next = _computeNextRecurringDue(
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
    _requireSignedIn();

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
      final next = _computeNextRecurringDue(
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
        id: generateReminderId(),
        reminderId: reminderId,
        type: ReminderEventType.missed,
        scheduledAt: scheduledAt,
        occurredAt: now,
      ),
    );

    await _recomputeSuggestion(reminderId);
  }

  Future<void> recoverStreak(String reminderId) async {
    if (!_modePremium) {
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

  Future<void> setNotificationIds(
    String reminderId, {
    int? mainId,
    int? preId,
    bool clearMain = false,
    bool clearPre = false,
  }) async {
    final reminder = await _activeStoreOrThrow().getReminder(reminderId);
    if (reminder == null) return;

    final nextMainId = clearMain ? null : (mainId ?? reminder.notifIdMain);
    final nextPreId = clearPre ? null : (preId ?? reminder.notifIdPre);
    final unchanged =
        reminder.notifIdMain == nextMainId && reminder.notifIdPre == nextPreId;
    if (unchanged) {
      return;
    }

    final updated = reminder.copyWith(
      notifIdMain: mainId,
      notifIdPre: preId,
      clearNotifIdMain: clearMain,
      clearNotifIdPre: clearPre,
      updatedAt: DateTime.now(),
    );
    await _writeReminder(updated);
  }

  Future<void> clearNotificationsForReminder(String reminderId) async {
    await setNotificationIds(reminderId, clearMain: true, clearPre: true);
  }

  Future<void> applySuggestion(String reminderId) async {
    if (!_modePremium) {
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
        ? _computeNextRecurringDue(
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
    final reminders = await _activeStoreOrThrow().listReminders();
    final events = await _activeStoreOrThrow().listEvents();

    double completionRate(Duration window) {
      final now = DateTime.now();
      final from = now.subtract(window);
      var complete = 0;
      var miss = 0;
      for (final e in events) {
        if (e.occurredAt.isBefore(from)) continue;
        if (e.type == ReminderEventType.completed) complete += 1;
        if (e.type == ReminderEventType.missed) miss += 1;
      }
      final denom = complete + miss;
      if (denom == 0) return 0;
      return complete / denom;
    }

    final missesByReminder = <String, int>{};
    for (final e in events) {
      if (e.type != ReminderEventType.missed) continue;
      missesByReminder[e.reminderId] =
          (missesByReminder[e.reminderId] ?? 0) + 1;
    }
    String? mostMissedId;
    var mostMissed = 0;
    missesByReminder.forEach((id, count) {
      if (count > mostMissed) {
        mostMissed = count;
        mostMissedId = id;
      }
    });

    final slots = <String, List<int>>{
      'Morning': [0, 0],
      'Afternoon': [0, 0],
      'Evening': [0, 0],
      'Night': [0, 0],
    };

    for (final e in events) {
      if (e.type != ReminderEventType.completed &&
          e.type != ReminderEventType.missed) {
        continue;
      }
      final hour = e.scheduledAt.hour;
      final key = hour >= 5 && hour < 12
          ? 'Morning'
          : hour >= 12 && hour < 17
          ? 'Afternoon'
          : hour >= 17 && hour < 22
          ? 'Evening'
          : 'Night';
      final bucket = slots[key]!;
      bucket[1] += 1;
      if (e.type == ReminderEventType.completed) bucket[0] += 1;
    }

    final performance = <String, double>{};
    for (final entry in slots.entries) {
      final complete = entry.value[0];
      final total = entry.value[1];
      performance[entry.key] = total == 0 ? 0 : complete / total;
    }

    var longestStreak = 0;
    for (final reminder in reminders) {
      if (reminder.longestStreak > longestStreak) {
        longestStreak = reminder.longestStreak;
      }
    }

    return ReminderAnalytics(
      weeklyCompletionRate: completionRate(const Duration(days: 7)),
      monthlyCompletionRate: completionRate(const Duration(days: 30)),
      mostMissedReminderId: mostMissedId,
      timeOfDayPerformance: performance,
      longestStreak: longestStreak,
    );
  }

  Future<ProductivityInsights> computeProductivityInsights({
    int contributionDays = 84,
  }) async {
    final reminders = await _activeStoreOrThrow().listReminders();
    final events = await _activeStoreOrThrow().listEvents();
    final summary = await computeAnalytics();

    final now = DateTime.now();
    final today = dayOnly(now);
    final dayBuckets = <int, _MutableDayBucket>{};
    final completedDayKeys = <int>{};

    for (final event in events) {
      final day = dayOnly(event.occurredAt);
      final key = day.millisecondsSinceEpoch;
      final bucket = dayBuckets.putIfAbsent(key, () => _MutableDayBucket(day));
      switch (event.type) {
        case ReminderEventType.completed:
          bucket.completed += 1;
          completedDayKeys.add(key);
          break;
        case ReminderEventType.missed:
          bucket.missed += 1;
          break;
        case ReminderEventType.snoozed:
          bucket.snoozed += 1;
          break;
      }
    }

    final safeContributionDays = contributionDays <= 0 ? 84 : contributionDays;
    final contributionStart = today.subtract(
      Duration(days: safeContributionDays - 1),
    );
    final contribution = <ProductivityDayStats>[];
    for (var i = 0; i < safeContributionDays; i += 1) {
      final day = contributionStart.add(Duration(days: i));
      final key = day.millisecondsSinceEpoch;
      final bucket = dayBuckets[key];
      contribution.add(
        ProductivityDayStats(
          day: day,
          completed: bucket?.completed ?? 0,
          missed: bucket?.missed ?? 0,
          snoozed: bucket?.snoozed ?? 0,
        ),
      );
    }

    final recentCount = contribution.length < 14 ? contribution.length : 14;
    final recentDays = contribution
        .skip(contribution.length - recentCount)
        .toList(growable: false);

    final completedToday =
        dayBuckets[today.millisecondsSinceEpoch]?.completed ?? 0;
    final missedToday = dayBuckets[today.millisecondsSinceEpoch]?.missed ?? 0;
    final snoozedToday = dayBuckets[today.millisecondsSinceEpoch]?.snoozed ?? 0;
    final pendingToday = reminders
        .where((r) => r.isActive && dayOnly(r.dueAt) == today)
        .length;
    final dueToday = completedToday + missedToday + pendingToday;

    final currentDayStreak = _computeCurrentDayStreak(
      today: today,
      completedDayKeys: completedDayKeys,
    );
    final bestDayStreak = _computeBestDayStreak(completedDayKeys);

    final weekFrom = now.subtract(const Duration(days: 7));
    var weekCompleted = 0;
    var weekSnoozed = 0;
    for (final event in events) {
      if (event.occurredAt.isBefore(weekFrom)) continue;
      if (event.type == ReminderEventType.completed) weekCompleted += 1;
      if (event.type == ReminderEventType.snoozed) weekSnoozed += 1;
    }
    final double weeklySnoozePerCompletion = weekCompleted == 0
        ? (weekSnoozed > 0 ? weekSnoozed.toDouble() : 0.0)
        : weekSnoozed / weekCompleted.toDouble();

    final slotCounters = <String, List<int>>{
      'Morning': [0, 0],
      'Afternoon': [0, 0],
      'Evening': [0, 0],
      'Night': [0, 0],
    };
    for (final event in events) {
      if (event.type != ReminderEventType.completed &&
          event.type != ReminderEventType.missed) {
        continue;
      }
      final key = _timeSlotForHour(event.scheduledAt.hour);
      final bucket = slotCounters[key]!;
      bucket[1] += 1;
      if (event.type == ReminderEventType.completed) {
        bucket[0] += 1;
      }
    }
    final slotPerformance = slotCounters.entries
        .map(
          (entry) => TimeSlotPerformance(
            label: entry.key,
            completed: entry.value[0],
            total: entry.value[1],
          ),
        )
        .toList(growable: false);

    String? bestFocusLabel;
    final eligibleSlots = slotPerformance.where((s) => s.total >= 3).toList();
    if (eligibleSlots.isNotEmpty) {
      eligibleSlots.sort((a, b) {
        final byRate = b.rate.compareTo(a.rate);
        if (byRate != 0) return byRate;
        return b.total.compareTo(a.total);
      });
      bestFocusLabel = eligibleSlots.first.label;
    }

    final monthFrom = now.subtract(const Duration(days: 30));
    final byReminder = <String, _ReminderAggregate>{};
    for (final event in events) {
      if (event.occurredAt.isBefore(monthFrom)) continue;
      final agg = byReminder.putIfAbsent(
        event.reminderId,
        () => _ReminderAggregate(event.reminderId),
      );
      switch (event.type) {
        case ReminderEventType.completed:
          agg.completed += 1;
          break;
        case ReminderEventType.missed:
          agg.missed += 1;
          break;
        case ReminderEventType.snoozed:
          agg.snoozed += 1;
          break;
      }
    }

    final riskStats = byReminder.values
        .where((a) => a.missed > 0 || a.snoozed > 0)
        .map(
          (a) => ReminderRiskStat(
            reminderId: a.reminderId,
            completedCount: a.completed,
            missedCount: a.missed,
            snoozedCount: a.snoozed,
          ),
        )
        .toList();
    riskStats.sort((a, b) {
      final byScore = b.riskScore.compareTo(a.riskScore);
      if (byScore != 0) return byScore;
      final byMissed = b.missedCount.compareTo(a.missedCount);
      if (byMissed != 0) return byMissed;
      return b.snoozedCount.compareTo(a.snoozedCount);
    });
    final atRiskReminders = riskStats.take(5).toList(growable: false);

    final performerStats = byReminder.values
        .where((a) => (a.completed + a.missed) >= 4)
        .map(
          (a) => ReminderRiskStat(
            reminderId: a.reminderId,
            completedCount: a.completed,
            missedCount: a.missed,
            snoozedCount: a.snoozed,
          ),
        )
        .toList();
    performerStats.sort((a, b) {
      final byRate = b.completionRate.compareTo(a.completionRate);
      if (byRate != 0) return byRate;
      return b.trackedCount.compareTo(a.trackedCount);
    });
    final topPerformers = performerStats.take(5).toList(growable: false);

    final streakScore = (currentDayStreak / 14).clamp(0, 1).toDouble();
    final snoozePenalty = (weeklySnoozePerCompletion / 2)
        .clamp(0, 1)
        .toDouble();
    final snoozeControl = 1 - snoozePenalty;
    final productivityScore =
        ((summary.weeklyCompletionRate * 45) +
                (summary.monthlyCompletionRate * 25) +
                (streakScore * 15) +
                (snoozeControl * 15))
            .round()
            .clamp(0, 100);

    return ProductivityInsights(
      summary: summary,
      productivityScore: productivityScore,
      currentDayStreak: currentDayStreak,
      bestDayStreak: bestDayStreak,
      completedToday: completedToday,
      missedToday: missedToday,
      snoozedToday: snoozedToday,
      dueToday: dueToday,
      pendingToday: pendingToday,
      weeklySnoozePerCompletion: weeklySnoozePerCompletion,
      bestFocusLabel: bestFocusLabel,
      slotPerformance: slotPerformance,
      contributionDays: contribution,
      recentDays: recentDays,
      atRiskReminders: atRiskReminders,
      topPerformers: topPerformers,
    );
  }

  Future<void> _recomputeSuggestion(String reminderId) async {
    final reminder = await _activeStoreOrThrow().getReminder(reminderId);
    if (reminder == null) return;

    int? suggestedMinute;
    String? message;

    if (reminder.consecutiveSnoozes >= 3) {
      final baseMinute = reminder.recurrence.timesOfDay.isNotEmpty
          ? reminder.recurrence.timesOfDay.first
          : minutesOfDay(reminder.dueAt);
      suggestedMinute = (baseMinute + 15) % 1440;
      message =
          'You snoozed this 3+ times. Would you like to move it to ${_formatMinute(suggestedMinute)}?';
    } else {
      final now = DateTime.now();
      final from = now.subtract(const Duration(days: 28));
      final events = await _activeStoreOrThrow().listEvents();
      final completionEvents = events.where((e) {
        return e.reminderId == reminder.id &&
            e.type == ReminderEventType.completed &&
            !e.occurredAt.isBefore(from);
      }).toList();

      if (completionEvents.length >= 5) {
        final completionMinutes =
            completionEvents
                .map((e) => minutesOfDay(e.occurredAt))
                .toList(growable: false)
              ..sort();
        final medianMinute = completionMinutes[completionMinutes.length ~/ 2];

        final closeCount = completionMinutes
            .where((m) => (m - medianMinute).abs() <= 30)
            .length;
        final consistency = closeCount / completionMinutes.length;

        final scheduledMinute = reminder.recurrence.timesOfDay.isNotEmpty
            ? reminder.recurrence.timesOfDay.first
            : minutesOfDay(reminder.dueAt);

        if ((medianMinute - scheduledMinute).abs() >= 30 &&
            consistency >= 0.7) {
          suggestedMinute = medianMinute;
          message =
              'You typically complete this at ${_formatMinute(medianMinute)}. Would you like to update the schedule?';
        }
      }
    }

    final updated = reminder.copyWith(
      suggestionMinutesOfDay: suggestedMinute,
      suggestionMessage: message,
      suggestionCreatedAt: suggestedMinute == null ? null : DateTime.now(),
      clearSuggestionMinutesOfDay: suggestedMinute == null,
      clearSuggestionMessage: message == null,
      clearSuggestionCreatedAt: suggestedMinute == null,
      updatedAt: DateTime.now(),
    );

    await _writeReminder(updated);
  }

  Future<void> _syncLocalToCloud() async {
    final local = _local;
    final cloud = _cloud;
    if (local == null || cloud == null) return;

    final reminders = await local.listReminders();
    final events = await local.listEvents();

    await cloud.upsertReminders(reminders);
    await cloud.upsertEvents(events);
  }

  Future<void> _syncCloudToLocal() async {
    final local = _local;
    final cloud = _cloud;
    if (local == null || cloud == null) return;

    final reminders = await cloud.listReminders();
    final events = await cloud.listEvents();

    await local.upsertReminders(reminders);
    await local.upsertEvents(events);
  }

  Future<void> _writeReminder(ReminderModel reminder) async {
    final active = _activeStoreOrThrow();
    try {
      await active.upsertReminder(reminder);
    } catch (e) {
      throw StateError(
        _cloudSyncEnabled
            ? 'Failed to write reminder to Firestore: $e'
            : 'Failed to write reminder to local storage: $e',
      );
    }

    if (_cloudSyncEnabled) {
      await _local?.upsertReminder(reminder);
    }
  }

  Future<void> _writeEvent(ReminderEvent event) async {
    final active = _activeStoreOrThrow();
    try {
      await active.upsertEvent(event);
    } catch (e) {
      throw StateError(
        _cloudSyncEnabled
            ? 'Failed to write reminder event to Firestore: $e'
            : 'Failed to write reminder event to local storage: $e',
      );
    }

    if (_cloudSyncEnabled) {
      await _local?.upsertEvent(event);
    }
  }

  ReminderStore _activeStoreOrThrow() {
    if (_cloudSyncEnabled) {
      final cloud = _cloud;
      if (cloud == null) {
        throw StateError('Cloud store unavailable.');
      }
      return cloud;
    }
    final local = _local;
    if (local == null) {
      throw StateError('Local store unavailable.');
    }
    return local;
  }

  void _requireSignedIn() {
    if (_user == null) {
      throw StateError('You must sign in first.');
    }
  }

  Future<void> _enforceFreeReminderLimitOrThrow(
    DateTime dueAt, {
    String? editingId,
  }) async {
    if (_modePremium) return;

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

    if (!_modePremium) {
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

  DateTime? _resolveInitialDue(
    DateTime dueAt,
    ReminderRecurrence recurrence, {
    required DateTime reference,
  }) {
    if (!recurrence.isRepeating) {
      return dueAt;
    }

    final minutes = recurrence.timesOfDay.isNotEmpty
        ? recurrence.timesOfDay.first
        : minutesOfDay(dueAt);

    final from = dueAt.isAfter(reference) ? dueAt : reference;

    return nextOccurrence(
      from: from,
      type: recurrence.type,
      days: recurrence.weekdays,
      minutes: minutes,
      intervalDays: recurrence.intervalDays,
      timesOfDay: recurrence.timesOfDay,
      anchorDate: dueAt,
      endAt: recurrence.endAt,
    );
  }

  DateTime? _computeNextRecurringDue({
    required DateTime from,
    required ReminderRecurrence recurrence,
    required DateTime anchor,
  }) {
    if (!recurrence.isRepeating) return null;

    final minutes = recurrence.timesOfDay.isNotEmpty
        ? recurrence.timesOfDay.first
        : minutesOfDay(anchor);

    return nextOccurrence(
      from: from,
      type: recurrence.type,
      days: recurrence.weekdays,
      minutes: minutes,
      intervalDays: recurrence.intervalDays,
      timesOfDay: recurrence.timesOfDay,
      anchorDate: anchor,
      endAt: recurrence.endAt,
    );
  }

  bool _isConsecutiveScheduledOccurrence(
    ReminderModel reminder,
    DateTime scheduledAt,
  ) {
    if (reminder.lastOccurrenceStatus != 'completed') return false;
    final prev = reminder.lastOccurrenceAt;
    if (prev == null) return false;

    if (!reminder.recurrence.isRepeating) {
      return dayOnly(prev) ==
          dayOnly(scheduledAt.subtract(const Duration(days: 1)));
    }

    final expected = _computeNextRecurringDue(
      from: prev.add(const Duration(seconds: 1)),
      recurrence: reminder.recurrence,
      anchor: prev,
    );
    if (expected == null) return false;

    final diff = expected.difference(scheduledAt).inMinutes.abs();
    return diff <= 1;
  }

  String _formatMinute(int minute) {
    final h = (minute ~/ 60) % 24;
    final m = minute % 60;
    final suffix = h >= 12 ? 'PM' : 'AM';
    final hour12 = h % 12 == 0 ? 12 : h % 12;
    final mm = m.toString().padLeft(2, '0');
    return '$hour12:$mm $suffix';
  }

  int _computeCurrentDayStreak({
    required DateTime today,
    required Set<int> completedDayKeys,
  }) {
    var streak = 0;
    var cursor = today;
    while (completedDayKeys.contains(cursor.millisecondsSinceEpoch)) {
      streak += 1;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  int _computeBestDayStreak(Set<int> completedDayKeys) {
    if (completedDayKeys.isEmpty) return 0;
    final ordered = completedDayKeys.toList()..sort();
    var best = 1;
    var current = 1;
    for (var i = 1; i < ordered.length; i += 1) {
      final prev = DateTime.fromMillisecondsSinceEpoch(ordered[i - 1]);
      final cur = DateTime.fromMillisecondsSinceEpoch(ordered[i]);
      if (dayOnly(cur) == dayOnly(prev.add(const Duration(days: 1)))) {
        current += 1;
      } else {
        current = 1;
      }
      if (current > best) best = current;
    }
    return best;
  }

  String _timeSlotForHour(int hour) {
    if (hour >= 5 && hour < 12) return 'Morning';
    if (hour >= 12 && hour < 17) return 'Afternoon';
    if (hour >= 17 && hour < 22) return 'Evening';
    return 'Night';
  }
}

class _MutableDayBucket {
  final DateTime day;
  int completed = 0;
  int missed = 0;
  int snoozed = 0;

  _MutableDayBucket(this.day);
}

class _ReminderAggregate {
  final String reminderId;
  int completed = 0;
  int missed = 0;
  int snoozed = 0;

  _ReminderAggregate(this.reminderId);
}
