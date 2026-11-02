import 'package:flutter/material.dart';

import '../../notifs.dart';
import '../../reliability/reliability.dart';

/// After a reminder is saved: if Android would delay or block its alarm,
/// says so once per session and links to the reliability check.
class AlarmPermissionPrompt {
  AlarmPermissionPrompt._();

  static bool _shownThisSession = false;

  static Future<void> maybeAsk(BuildContext context) async {
    if (_shownThisSession) return;
    final status = await Notifs.permissions();
    if (status.allGranted || !context.mounted) return;
    _shownThisSession = true;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 8),
        content: Text(
          status.notificationsEnabled
              ? 'This alarm may ring late: Snooze isn’t allowed to set '
                    'exact alarms.'
              : 'This reminder can’t alert you: notifications are off.',
        ),
        action: SnackBarAction(
          label: 'Fix',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const ReliabilityCheckPage(),
            ),
          ),
        ),
      ),
    );
  }
}
