import 'dart:async';

import 'package:flutter/foundation.dart';

import 'alarm_ui.dart';
import 'notifs.dart';
import 'reminder_model.dart';
import 'reminder_service.dart';
import 'scheduling/alert_payload.dart';
import 'scheduling/schedule_planner.dart';

/// Keeps the OS's scheduled notifications in line with the reminders.
///
/// Every sync plans each reminder (see [planReminder]), then reconciles with
/// what the OS has pending: stale alerts are cancelled, missing or changed
/// ones are posted, and alerts already on screen are left alone. Notification
/// IDs are derived from reminder + occurrence, so syncing is idempotent and
/// nothing is written back to the store while scheduling.
class ReminderScheduler {
  ReminderScheduler._();

  static const PlannerConfig config = PlannerConfig();

  static ReminderService? _service;
  static StreamSubscription<List<ReminderModel>>? _sub;
  static Future<void> _queue = Future<void>.value();

  /// Signature of each alert this isolate posted, by notification ID, so an
  /// unchanged alert isn't re-posted on every data change.
  static final Map<int, String> _posted = <int, String>{};

  static void configure(ReminderService service) {
    _service = service;
  }

  static Future<void> start() async {
    final service = _requireService();
    await _sub?.cancel();
    _sub = service.watchReminders().listen((items) {
      _enqueue(() => _sync(service, items));
    });
  }

  /// Re-plans every reminder from the store and re-posts every alert. Used on
  /// app resume and by the background re-arm job (reboot, time or time-zone
  /// change, periodic check), which may run after the OS dropped alarms.
  static Future<void> rearmNow() {
    final service = _requireService();
    final done = Completer<void>();
    _enqueue(() async {
      try {
        _posted.clear();
        await Notifs.refreshTimeZone();
        await _sync(service, await service.listReminders());
      } finally {
        done.complete();
      }
    });
    return done.future;
  }

  /// Re-plans one reminder and reconciles only its own alerts. Used by the
  /// notification-action background isolate, which has no live stream.
  static Future<void> replanOne(ReminderModel reminder) {
    final service = _requireService();
    return _sync(service, [reminder], onlyReminderIds: {reminder.id});
  }

  /// Cancels every pending alert of a reminder that no longer exists.
  static Future<void> cancelReminder(String reminderId) async {
    for (final pending in await Notifs.pendingAlerts()) {
      if (pending.payload?.reminderId == reminderId) {
        await Notifs.cancel(pending.id);
        _posted.remove(pending.id);
      }
    }
  }

  static Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _queue = Future<void>.value();
    _posted.clear();
  }

  /// Sign-out: nothing from the previous account may ring afterwards.
  static Future<void> stopAndCancelAll() async {
    await stop();
    await _guard('cancel all notifications', Notifs.cancelAll);
  }

  static ReminderService _requireService() {
    final service = _service;
    if (service == null) {
      throw StateError('ReminderScheduler not configured.');
    }
    return service;
  }

  /// Runs scheduling jobs one at a time. A failing job is logged and the
  /// queue keeps going, so one bad reminder can't stop all scheduling.
  static void _enqueue(Future<void> Function() job) {
    _queue = _queue.then((_) => job()).catchError((Object e, StackTrace s) {
      debugPrint('Reminder scheduling failed: $e\n$s');
    });
  }

  static Future<void> _sync(
    ReminderService service,
    List<ReminderModel> reminders, {
    Set<String>? onlyReminderIds,
    bool resolve = true,
  }) async {
    final now = DateTime.now();
    final desired = <int, PlannedAlert>{};
    final toResolve = <String>{};
    for (final reminder in reminders) {
      try {
        final plan = planReminder(reminder, now, config: config);
        if (plan.needsMissedOrAdvance) toResolve.add(reminder.id);
        for (final alert in plan.alerts) {
          desired[alert.id] = alert;
        }
      } catch (e, s) {
        debugPrint('Planning reminder ${reminder.id} failed: $e\n$s');
      }
    }

    var pending = const <PendingAlert>[];
    try {
      pending = await Notifs.pendingAlerts();
    } catch (e) {
      debugPrint('Reading pending notifications failed: $e');
    }
    final onScreen = <int>{...AlarmUi.onScreenNotificationIds};
    try {
      onScreen.addAll(await Notifs.activeIds());
    } catch (e) {
      debugPrint('Reading active notifications failed: $e');
    }

    final pendingIds = <int>{};
    for (final p in pending) {
      final owner = p.payload?.reminderId;
      if (onlyReminderIds != null && !onlyReminderIds.contains(owner)) {
        continue;
      }
      pendingIds.add(p.id);
      if (desired.containsKey(p.id)) continue;
      // A reminder about to be moved on is reconciled once that's done
      // (below), so its upcoming alarms don't disappear in between.
      if (resolve && toResolve.contains(owner)) continue;
      await _guard('cancel stale alert ${p.id}', () => Notifs.cancel(p.id));
      _posted.remove(p.id);
    }

    final ordered = desired.values.toList()
      ..sort((a, b) => a.fireAt.compareTo(b.fireAt));
    for (final alert in ordered) {
      if (onScreen.contains(alert.id)) continue;
      if (pendingIds.contains(alert.id) &&
          _posted[alert.id] == alert.signature) {
        continue;
      }
      // Posting takes time; never hand the OS a time that has just passed.
      final earliest = DateTime.now().add(config.catchUpDelay);
      final fireAt = alert.fireAt.isBefore(earliest) ? earliest : alert.fireAt;
      final ok = await _guard(
        'schedule alert ${alert.id}',
        () => _post(alert, fireAt),
      );
      if (ok) _posted[alert.id] = alert.signature;
    }

    if (!resolve || toResolve.isEmpty) return;
    for (final id in toResolve) {
      await _guard(
        'resolve missed reminder $id',
        () => service.markReminderMissedOrAdvance(id),
      );
    }
    // Plan them again from the store now rather than wait for a change
    // event: the background re-arm job has no live stream, and when another
    // isolate (app vs. background job) already moved a reminder on,
    // resolving changes nothing here, so no event would ever come.
    final fresh = <ReminderModel>[];
    for (final id in toResolve) {
      try {
        final reminder = await service.getReminder(id);
        if (reminder != null) fresh.add(reminder);
      } catch (e) {
        debugPrint('Reading reminder $id failed: $e');
      }
    }
    await _sync(service, fresh, onlyReminderIds: toResolve, resolve: false);
  }

  static Future<bool> _guard(String what, Future<void> Function() op) async {
    try {
      await op();
      return true;
    } catch (e, s) {
      debugPrint('$what failed: $e\n$s');
      return false;
    }
  }

  static Future<void> _post(PlannedAlert alert, DateTime fireAt) {
    final reminder = alert.reminder;
    final level = switch (reminder.priority) {
      ReminderPriority.low => AlarmPriorityLevel.low,
      ReminderPriority.medium => AlarmPriorityLevel.medium,
      ReminderPriority.high => AlarmPriorityLevel.high,
    };
    switch (alert.kind) {
      case AlertKind.alarm:
        return Notifs.schedule(
          id: alert.id,
          title: alert.title,
          body: alert.body,
          whenLocal: fireAt,
          payload: alert.payload,
          isAlarm: true,
          alarmSoundId: reminder.alarmSoundId,
          enableActions: reminder.alertMode == ReminderAlertMode.ringAndNotify,
          priorityLevel: level,
          timeoutAfter: config.ringWindow,
        );
      case AlertKind.notify:
        return Notifs.schedule(
          id: alert.id,
          title: alert.title,
          body: alert.body,
          whenLocal: fireAt,
          payload: alert.payload,
          notificationSoundId: reminder.notificationSoundId,
          enableActions: false,
          priorityLevel: level,
        );
      case AlertKind.pre:
        return Notifs.schedule(
          id: alert.id,
          title: alert.title,
          body: alert.body,
          whenLocal: fireAt,
          payload: alert.payload,
          notificationSoundId: reminder.notificationSoundId,
          enableActions: false,
        );
    }
  }
}
