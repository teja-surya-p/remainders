import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'alarm_popup_service.dart';
import 'app_services.dart';
import 'background/rearm_job.dart';
import 'components/common/app_loading.dart';
import 'crash_reporter.dart';
import 'firebase_options.dart';
import 'notifs.dart';
import 'onboarding/onboarding_page.dart';
import 'pages/home_page.dart';
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
          // Screens without an app bar get the right status-bar icons too.
          builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
            value: AppTheme.overlayStyleFor(Theme.of(context).brightness),
            child: child ?? const SizedBox.shrink(),
          ),
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
    _init = _initializeAndReport();
  }

  /// Start-up failures show a retry screen; the cause goes to the log and,
  /// if Firebase got that far, to crash reporting.
  Future<void> _initializeAndReport() =>
      _initialize().catchError((Object e, StackTrace s) {
        CrashReporter.record(e, s, reason: 'App start failed');
        Error.throwWithStackTrace(e, s);
      });

  Future<void> _initialize() async {
    // Works offline; only the optional sign-in and backup use it.
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(
      const Duration(seconds: 15),
      onTimeout: () =>
          throw TimeoutException('Firebase initialization timed out.'),
    );
    await CrashReporter.init();

    await AppServices.initialize().timeout(
      const Duration(seconds: 12),
      onTimeout: () =>
          throw TimeoutException('App services initialization timed out.'),
    );

    try {
      await Notifs.init(
        onAction: (r) {
          unawaited(SnoozeHandler.handle(r, openCustomUi: true));
        },
        onBackgroundAction: notificationTapBackground,
      ).timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('Notification init skipped: $e');
    }

    // Background re-arm: periodic safety net, plus immediate runs after
    // reboot, app update, and time or time-zone changes (RearmReceiver.kt).
    try {
      await registerRearmJobs().timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('Background re-arm jobs not registered: $e');
    }

    // Reminders live on the device and need no account: start the alarm
    // engine right away, signed in or not.
    ReminderScheduler.configure(AppServices.reminders);
    await ReminderScheduler.start();
    AlarmPopupService.configure(AppServices.reminders);
    await AlarmPopupService.start();
  }

  void _retryInit() {
    setState(() {
      _handledLaunch = false;
      _init = _initializeAndReport();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _init,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const AppLoadingScaffold(label: 'Starting Snooze...');
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
                      "Snooze couldn't start",
                      style: Theme.of(context).textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Please try again. If this keeps happening, restart '
                      'your phone.',
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
              unawaited(SnoozeHandler.handle(r, openCustomUi: true));
            }
          });
        }

        return const _AppShell();
      },
    );
  }
}

/// The running app: always the home screen. Signing in (optional) only turns
/// on backup; it never blocks the reminders.
class _AppShell extends StatefulWidget {
  const _AppShell();

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> with WidgetsBindingObserver {
  StreamSubscription<User?>? _authSub;
  late Future<bool> _onboarded = OnboardingState.isDone();

  Future<void> _finishOnboarding() async {
    await OnboardingState.markDone();
    // Permissions may have changed: re-post alarms (exact if now allowed).
    unawaited(ReminderScheduler.rearmNow());
    if (mounted) {
      setState(() {
        _onboarded = Future.value(true);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authSub = FirebaseAuth.instance.authStateChanges().listen(
      (user) => unawaited(_onAccountChanged(user)),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_authSub?.cancel());
    super.dispose();
  }

  Future<void> _onAccountChanged(User? user) async {
    try {
      await AppServices.attachAccount(user);
      if (user != null) await UserStore.saveUser(user);
    } catch (e) {
      debugPrint('Updating the account failed: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshAfterResume());
    }
  }

  /// Picks up anything changed while the app was in the background (a snooze
  /// from the notification, a time-zone change) and re-checks every alarm.
  Future<void> _refreshAfterResume() async {
    try {
      await AppServices.reminders.reloadLocal();
      await ReminderScheduler.rearmNow();
    } catch (e) {
      debugPrint('Refresh after resume failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _onboarded,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const AppLoadingScaffold(label: '');
        if (snapshot.data == false) {
          return OnboardingPage(onDone: _finishOnboarding);
        }
        return const HomePage();
      },
    );
  }
}
