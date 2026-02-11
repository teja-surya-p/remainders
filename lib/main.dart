import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_options.dart';
import 'home_page.dart';
import 'notifs.dart';
import 'reminder_scheduler.dart';
import 'snooze_handler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
      home: const _Bootstrap(),
    );
  }
}

class _Bootstrap extends StatefulWidget {
  const _Bootstrap();

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  late final Future<void> _init = _initialize();
  bool _handledLaunch = false;

  Future<void> _initialize() async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await FirebaseAuth.instance.signInAnonymously();
    await Notifs.init(
      onAction: (r) {
        SnoozeHandler.handle(r, openCustomUi: true);
      },
      onBackgroundAction: notificationTapBackground,
    );
    await ReminderScheduler.start();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _init,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Text('Init error: ${snapshot.error}'),
            ),
          );
        }
        if (!_handledLaunch) {
          _handledLaunch = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final r = Notifs.takePendingLaunchResponse();
            if (r != null) {
              SnoozeHandler.handle(r, openCustomUi: true);
            }
          });
        }
        return const HomePage();
      },
    );
  }
}
