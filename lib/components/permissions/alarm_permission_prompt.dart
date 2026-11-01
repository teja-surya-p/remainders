import 'dart:async';

import 'package:flutter/material.dart';

import '../../notifs.dart';
import '../../reminder_scheduler.dart';

/// Asks for what reliable alarms need (notifications + exact alarms) when
/// either is missing. Shown at most once per app session; the onboarding
/// reliability setup (M5) replaces this as the main entry point.
class AlarmPermissionPrompt {
  AlarmPermissionPrompt._();

  static bool _askedThisSession = false;

  static Future<void> maybeAsk(BuildContext context) async {
    if (_askedThisSession) return;
    final status = await Notifs.permissions();
    if (status.allGranted || !context.mounted) return;
    _askedThisSession = true;

    final allow = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Let Snooze ring on time'),
        content: Text(
          status.notificationsEnabled
              ? 'Android needs the "Alarms & reminders" permission for exact '
                    'alarms. Without it, reminders can arrive several minutes late.'
              : 'Snooze needs permission to show notifications and set exact '
                    'alarms. Without it, reminders can be silent or late.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Allow'),
          ),
        ],
      ),
    );
    if (allow != true) return;

    await Notifs.requestAlarmPermissions();
    // Re-post existing alarms so they switch to exact scheduling.
    unawaited(ReminderScheduler.rearmNow());
  }
}
