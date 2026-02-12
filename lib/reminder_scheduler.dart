import 'dart:async';

import 'notifs.dart';
import 'reminder_model.dart';
import 'reminder_service.dart';

class ReminderScheduler {
  ReminderScheduler._();

  static const Duration _leadTime = Duration(minutes: 30);
  static const Duration _pastDueGrace = Duration(minutes: 2);
  static const int _maxNotifId = 2147483647;

  static ReminderService? _service;
  static StreamSubscription<List<ReminderModel>>? _sub;
  static final Map<String, _ScheduleSnapshot> _scheduled =
      <String, _ScheduleSnapshot>{};
  static Future<void> _queue = Future<void>.value();

  static void configure(ReminderService service) {
    _service = service;
  }

  static Future<void> start() async {
    final service = _service;
    if (service == null) {
      throw StateError('ReminderScheduler not configured.');
    }

    await _sub?.cancel();
    _sub = service.watchReminders().listen((items) {
      _queue = _queue.then((_) => _handleItems(service, items));
      unawaited(_queue);
    });
  }

  static Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _queue = Future<void>.value();
    _scheduled.clear();
  }

  static Future<void> _handleItems(
    ReminderService service,
    List<ReminderModel> reminders,
  ) async {
    final ids = reminders.map((e) => e.id).toSet();
    final removed = _scheduled.keys.where((id) => !ids.contains(id)).toList();
    for (final id in removed) {
      final snapshot = _scheduled.remove(id);
      if (snapshot != null) {
        await _cancelIds(snapshot.mainId, snapshot.preId, snapshot.secondaryId);
      }
    }

    for (final reminder in reminders) {
      await _handleReminder(service, reminder);
    }
  }

  static Future<void> _handleReminder(
    ReminderService service,
    ReminderModel reminder,
  ) async {
    final previous = _scheduled[reminder.id];
    final knownMain = reminder.notifIdMain ?? previous?.mainId;
    final knownPre = reminder.notifIdPre ?? previous?.preId;
    final knownSecondary = previous?.secondaryId;

    if (reminder.completed || reminder.missed) {
      await _cancelIds(knownMain, knownPre, knownSecondary);
      _scheduled.remove(reminder.id);
      if (reminder.notifIdMain != null || reminder.notifIdPre != null) {
        await service.clearNotificationsForReminder(reminder.id);
      }
      return;
    }

    final now = DateTime.now();
    if (reminder.dueAt.isBefore(now.subtract(_pastDueGrace))) {
      await _cancelIds(knownMain, knownPre, knownSecondary);
      _scheduled.remove(reminder.id);
      await service.markReminderMissedOrAdvance(reminder.id);
      return;
    }

    final dueAtForSchedule = reminder.dueAt.isBefore(now)
        ? now.add(const Duration(seconds: 2))
        : reminder.dueAt;

    final preTime = dueAtForSchedule.subtract(_leadTime);
    final shouldPre = preTime.isAfter(now);

    final mainId = knownMain ?? _nextId();
    final ringAndNotify = reminder.alertMode == ReminderAlertMode.ringAndNotify;
    final secondaryId = ringAndNotify ? _deriveId(mainId, 1) : null;
    final preOffset = ringAndNotify ? 2 : 1;
    final preId = shouldPre ? (knownPre ?? _deriveId(mainId, preOffset)) : null;

    final signature = [
      reminder.dueAt.millisecondsSinceEpoch,
      mainId,
      preId,
      secondaryId,
      reminder.title,
      reminder.description ?? '',
      reminderAlertModeToString(reminder.alertMode),
      reminderPriorityToString(reminder.priority),
      shouldPre,
    ].join('|');

    if (signature == previous?.signature) {
      return;
    }

    final oldIds = <int>{};
    if (previous != null) {
      oldIds.add(previous.mainId);
      if (previous.preId != null) oldIds.add(previous.preId!);
      if (previous.secondaryId != null) oldIds.add(previous.secondaryId!);
    } else {
      if (reminder.notifIdMain != null) oldIds.add(reminder.notifIdMain!);
      if (reminder.notifIdPre != null) oldIds.add(reminder.notifIdPre!);
    }
    final newIds = <int>{
      mainId,
      if (preId != null) preId,
      if (secondaryId != null) secondaryId,
    };
    for (final id in oldIds) {
      if (!newIds.contains(id)) {
        await Notifs.cancel(id);
      }
    }

    final shouldWriteIds =
        reminder.notifIdMain != mainId ||
        reminder.notifIdPre != preId ||
        (!shouldPre && reminder.notifIdPre != null);
    if (shouldWriteIds) {
      await service.setNotificationIds(
        reminder.id,
        mainId: mainId,
        preId: preId,
        clearPre: !shouldPre,
      );
    }

    final title = _titleWithSnoozeCount(reminder);
    final body = _bodyWithSnoozeCount(reminder.description, reminder);

    await Notifs.cancel(mainId);
    await _schedulePrimary(
      reminder: reminder,
      id: mainId,
      title: title,
      body: body,
      whenLocal: dueAtForSchedule,
    );

    if (secondaryId != null) {
      await Notifs.cancel(secondaryId);
      await Notifs.schedule(
        id: secondaryId,
        title: title,
        body: body,
        whenLocal: dueAtForSchedule,
        payload: 'notify:${reminder.id}',
        playSound: false,
        enableVibration: false,
        enableActions: false,
      );
    }

    if (shouldPre && preId != null) {
      await Notifs.cancel(preId);
      await Notifs.schedule(
        id: preId,
        title: _upcomingTitle(reminder),
        body: _upcomingBody(reminder),
        whenLocal: preTime,
        payload: 'pre:${reminder.id}',
        playSound: false,
        enableVibration: false,
        enableActions: false,
      );
    }

    _scheduled[reminder.id] = _ScheduleSnapshot(
      signature: signature,
      mainId: mainId,
      preId: preId,
      secondaryId: secondaryId,
    );
  }

  static Future<void> _schedulePrimary({
    required ReminderModel reminder,
    required int id,
    required String title,
    required String? body,
    required DateTime whenLocal,
  }) async {
    final level = _priorityLevel(reminder.priority);
    switch (reminder.alertMode) {
      case ReminderAlertMode.notifyOnly:
        await Notifs.schedule(
          id: id,
          title: title,
          body: body,
          whenLocal: whenLocal,
          payload: 'notify:${reminder.id}',
          playSound: false,
          enableVibration: false,
          enableActions: false,
          priorityLevel: level,
        );
        return;
      case ReminderAlertMode.ringOnly:
        await Notifs.schedule(
          id: id,
          title: title,
          body: body,
          whenLocal: whenLocal,
          payload: 'alarm:${reminder.id}',
          isAlarm: true,
          enableActions: false,
          priorityLevel: level,
        );
        return;
      case ReminderAlertMode.ringAndNotify:
        await Notifs.schedule(
          id: id,
          title: title,
          body: body,
          whenLocal: whenLocal,
          payload: 'alarm:${reminder.id}',
          isAlarm: true,
          priorityLevel: level,
        );
        return;
    }
  }

  static String _titleWithSnoozeCount(ReminderModel reminder) {
    if (reminder.consecutiveSnoozes < 1) {
      return reminder.title;
    }
    return '${reminder.title} (${reminder.consecutiveSnoozes}x snoozed)';
  }

  static String? _bodyWithSnoozeCount(
    String? baseBody,
    ReminderModel reminder,
  ) {
    final cleaned = baseBody?.trim();
    if (reminder.consecutiveSnoozes < 1) {
      return cleaned?.isEmpty == true ? null : cleaned;
    }
    final suffix = 'Snoozed ${reminder.consecutiveSnoozes} times';
    if (cleaned == null || cleaned.isEmpty) {
      return suffix;
    }
    return '$cleaned • $suffix';
  }

  static String _upcomingBody(ReminderModel reminder) {
    final label = reminder.alertMode == ReminderAlertMode.ringOnly
        ? 'Alarm'
        : 'Reminder';
    final base = '$label: ${reminder.title} in ${_leadTime.inMinutes} minutes';
    if (reminder.consecutiveSnoozes < 1) {
      return base;
    }
    return '$base • ${reminder.consecutiveSnoozes}x snoozed';
  }

  static String _upcomingTitle(ReminderModel reminder) {
    if (reminder.alertMode == ReminderAlertMode.ringOnly) {
      return 'Upcoming alarm';
    }
    return 'Upcoming reminder';
  }

  static AlarmPriorityLevel _priorityLevel(ReminderPriority priority) {
    switch (priority) {
      case ReminderPriority.low:
        return AlarmPriorityLevel.low;
      case ReminderPriority.medium:
        return AlarmPriorityLevel.medium;
      case ReminderPriority.high:
        return AlarmPriorityLevel.high;
    }
  }

  static Future<void> _cancelIds(
    int? mainId,
    int? preId,
    int? secondaryId,
  ) async {
    final ids = <int>{
      if (mainId != null) mainId,
      if (preId != null) preId,
      if (secondaryId != null) secondaryId,
    };
    for (final id in ids) {
      await Notifs.cancel(id);
    }
  }

  static int _deriveId(int base, int offset) {
    final id = (base + offset) % _maxNotifId;
    return id <= 0 ? 1 : id;
  }

  static int _nextId() {
    final id = DateTime.now().millisecondsSinceEpoch % _maxNotifId;
    return id <= 0 ? 1 : id;
  }
}

class _ScheduleSnapshot {
  final String signature;
  final int mainId;
  final int? preId;
  final int? secondaryId;

  const _ScheduleSnapshot({
    required this.signature,
    required this.mainId,
    required this.preId,
    required this.secondaryId,
  });
}
