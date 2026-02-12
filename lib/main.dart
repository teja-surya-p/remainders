import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'alarm_popup_service.dart';
import 'app_services.dart';
import 'components/common/app_loading.dart';
import 'pages/auth_page.dart';
import 'firebase_options.dart';
import 'pages/home_page.dart';
import 'notifs.dart';
import 'reminder_scheduler.dart';
import 'snooze_handler.dart';
import 'theme/app_theme.dart';
import 'user_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppServices.theme,
      builder: (context, _) {
        return MaterialApp(
          navigatorKey: Notifs.navKey,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: AppServices.theme.themeMode,
          home: const _Bootstrap(),
        );
      },
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

    await AppServices.initialize();

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
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _init,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const AppLoadingScaffold();
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(child: Text('Init error: ${snapshot.error}')),
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

        return const _AuthGate();
      },
    );
  }
}

class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  String? _activeUid;
  Future<void>? _bindFuture;

  Future<void> _bind(User user) async {
    await AppServices.bindUser(user);
    await UserStore.saveUser(user);

    ReminderScheduler.configure(AppServices.reminders);
    await ReminderScheduler.start();
    AlarmPopupService.configure(AppServices.reminders);
    await AlarmPopupService.start();
  }

  Future<void> _unbind() async {
    await AlarmPopupService.stop();
    await ReminderScheduler.stop();
    await AppServices.unbindUser();
  }

  Future<void> _ensureBound(User user) {
    if (_activeUid == user.uid && _bindFuture != null) {
      return _bindFuture!;
    }
    _activeUid = user.uid;
    _bindFuture = _bind(user);
    return _bindFuture!;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AppLoadingScaffold();
        }

        final user = snapshot.data;
        if (user == null) {
          if (_activeUid != null) {
            _activeUid = null;
            _bindFuture = null;
            _unbind();
          }
          return const SignInPage();
        }

        return FutureBuilder<void>(
          future: _ensureBound(user),
          builder: (context, bindSnapshot) {
            if (bindSnapshot.connectionState != ConnectionState.done) {
              return const AppLoadingScaffold();
            }
            if (bindSnapshot.hasError) {
              return Scaffold(
                body: Center(child: Text('Bind error: ${bindSnapshot.error}')),
              );
            }
            return const HomePage();
          },
        );
      },
    );
  }
}
