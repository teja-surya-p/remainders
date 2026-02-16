import 'dart:async';

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
  late Future<void> _init;
  bool _handledLaunch = false;

  @override
  void initState() {
    super.initState();
    _init = _initialize();
  }

  Future<void> _initialize() async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(
      const Duration(seconds: 15),
      onTimeout: () =>
          throw TimeoutException('Firebase initialization timed out.'),
    );

    await AppServices.initialize().timeout(
      const Duration(seconds: 12),
      onTimeout: () =>
          throw TimeoutException('App services initialization timed out.'),
    );

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

  void _retryInit() {
    setState(() {
      _handledLaunch = false;
      _init = _initialize();
    });
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
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Init error: ${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _retryInit,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
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
    await AppServices.bindUser(user).timeout(
      const Duration(seconds: 15),
      onTimeout: () =>
          throw TimeoutException('User binding timed out while loading data.'),
    );
    await UserStore.saveUser(user).timeout(
      const Duration(seconds: 5),
      onTimeout: () =>
          throw TimeoutException('Failed to persist user session.'),
    );

    ReminderScheduler.configure(AppServices.reminders);
    await ReminderScheduler.start().timeout(
      const Duration(seconds: 8),
      onTimeout: () =>
          throw TimeoutException('Reminder scheduler start timed out.'),
    );
    AlarmPopupService.configure(AppServices.reminders);
    await AlarmPopupService.start().timeout(
      const Duration(seconds: 8),
      onTimeout: () =>
          throw TimeoutException('Alarm popup service start timed out.'),
    );
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
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Bind error: ${bindSnapshot.error}',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: () {
                            setState(() {
                              _bindFuture = null;
                            });
                          },
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }
            return const HomePage();
          },
        );
      },
    );
  }
}
