import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../app_services.dart';
import '../firebase_options.dart';
import '../notifs.dart';
import '../reminder_scheduler.dart';

/// Periodic safety net: re-plans every reminder every 15 minutes, which also
/// tops up scheduled-ahead repeats and records misses with the app closed.
const String kRearmPeriodicTask = 'snooze.rearm.periodic';

/// Immediate re-arm. Also enqueued natively by RearmReceiver.kt on boot, app
/// update, and time or time-zone changes — keep the name in sync with it.
const String kRearmNowTask = 'snooze.rearm.now';

@pragma('vm:entry-point')
void rearmCallbackDispatcher() {
  Workmanager().executeTask((task, _) async {
    try {
      await rearmFromBackground();
      return true;
    } catch (e, s) {
      debugPrint('Background re-arm ($task) failed: $e\n$s');
      // WorkManager retries a failed one-off task with backoff.
      return false;
    }
  });
}

/// Re-plans all reminders in a background isolate (no UI, no app state).
Future<void> rearmFromBackground() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Notifs.ensureTimeZone();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } on FirebaseException catch (e) {
    if (e.code != 'duplicate-app') rethrow;
  }
  await AppServices.initialize();

  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return; // Signed out: nothing should ring.
  await AppServices.bindUser(user);
  ReminderScheduler.configure(AppServices.reminders);
  await ReminderScheduler.rearmNow();
}

/// Registers the background jobs. Safe to call on every launch.
Future<void> registerRearmJobs() async {
  if (defaultTargetPlatform != TargetPlatform.android) return;
  await Workmanager().initialize(rearmCallbackDispatcher);
  await Workmanager().registerPeriodicTask(
    kRearmPeriodicTask,
    kRearmPeriodicTask,
    frequency: const Duration(minutes: 15),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
  );
}
