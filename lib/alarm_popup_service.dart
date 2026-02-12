import 'dart:async';

import 'package:flutter/material.dart';

import 'notifs.dart';
import 'pages/alarm_screen.dart';
import 'reminder_model.dart';
import 'reminder_service.dart';

class AlarmPopupService {
  AlarmPopupService._();

  static const Duration _tick = Duration(seconds: 1);
  static const Duration _triggerWindow = Duration(minutes: 2);
  static const Duration _leadTolerance = Duration(seconds: 2);

  static ReminderService? _service;
  static StreamSubscription<List<ReminderModel>>? _sub;
  static Timer? _timer;
  static List<ReminderModel> _latest = const <ReminderModel>[];
  static final Set<String> _shownOccurrences = <String>{};
  static String? _activeOccurrence;
  static bool _sweeping = false;

  static void configure(ReminderService service) {
    _service = service;
  }

  static Future<void> start() async {
    final service = _service;
    if (service == null) {
      throw StateError('AlarmPopupService not configured.');
    }

    await _sub?.cancel();
    _sub = service.watchReminders().listen((items) {
      _latest = items;
      unawaited(_sweep());
    });

    _timer?.cancel();
    _timer = Timer.periodic(_tick, (_) {
      unawaited(_sweep());
    });
  }

  static Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    await _sub?.cancel();
    _sub = null;
    _latest = const <ReminderModel>[];
    _shownOccurrences.clear();
    _activeOccurrence = null;
  }

  static Future<void> _sweep() async {
    if (_sweeping) return;
    _sweeping = true;
    try {
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (lifecycle != AppLifecycleState.resumed) {
        return;
      }

      final nav = Notifs.navKey.currentState;
      if (nav == null || _activeOccurrence != null) {
        return;
      }

      final now = DateTime.now();
      final activeKeys = <String>{};
      for (final reminder in _latest) {
        if (reminder.completed || reminder.missed) continue;
        if (!_requiresAlarmUi(reminder.alertMode)) continue;
        activeKeys.add(
          '${reminder.id}:${reminder.dueAt.millisecondsSinceEpoch}',
        );
      }
      _shownOccurrences.removeWhere((key) => !activeKeys.contains(key));

      for (final reminder in _latest) {
        if (reminder.completed || reminder.missed) continue;
        if (!_requiresAlarmUi(reminder.alertMode)) continue;

        final dueAt = reminder.dueAt;
        if (dueAt.isAfter(now.add(_leadTolerance))) continue;
        if (now.difference(dueAt) > _triggerWindow) continue;

        final occurrenceKey = '${reminder.id}:${dueAt.millisecondsSinceEpoch}';
        if (_shownOccurrences.contains(occurrenceKey)) continue;

        _shownOccurrences.add(occurrenceKey);
        _activeOccurrence = occurrenceKey;

        final mainId = reminder.notifIdMain;
        if (mainId != null) {
          await Notifs.cancel(mainId);
        }

        unawaited(
          nav
              .push(
                MaterialPageRoute<void>(
                  builder: (_) => AlarmScreen(reminderId: reminder.id),
                  fullscreenDialog: true,
                ),
              )
              .whenComplete(() {
                if (_activeOccurrence == occurrenceKey) {
                  _activeOccurrence = null;
                }
              }),
        );
        break;
      }
    } finally {
      _sweeping = false;
    }
  }

  static bool _requiresAlarmUi(ReminderAlertMode mode) {
    return mode == ReminderAlertMode.ringOnly ||
        mode == ReminderAlertMode.ringAndNotify;
  }
}
