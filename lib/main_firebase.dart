import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'alarm_popup_service.dart';
import 'app_services.dart';
import 'firebase_options.dart';
import 'pages/home_page.dart';
import 'notifs.dart';
import 'reminder_scheduler.dart';
import 'snooze_handler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await AppServices.initialize();

  await FirebaseAuth.instance.signInAnonymously();
  final user = FirebaseAuth.instance.currentUser;
  if (user != null) {
    await AppServices.bindUser(user);
    ReminderScheduler.configure(AppServices.reminders);
    await ReminderScheduler.start();
    AlarmPopupService.configure(AppServices.reminders);
    await AlarmPopupService.start();
  }

  try {
    await Notifs.init(
      onAction: (r) {
        SnoozeHandler.handle(r, openCustomUi: true);
      },
      onBackgroundAction: notificationTapBackground,
    ).timeout(const Duration(seconds: 8));
  } catch (e) {
    debugPrint('Notification init skipped: $e');
  }

  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: Notifs.navKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: const HomePage(),
    );
  }
}
