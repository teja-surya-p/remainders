import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Crash and error reports through Firebase Crashlytics, from the app's main
/// isolate. Collection is off in debug builds. Background isolates don't
/// start Firebase, so their errors are only logged.
class CrashReporter {
  CrashReporter._();

  static bool _ready = false;

  /// Call once, right after Firebase starts.
  static Future<void> init() async {
    try {
      final crashlytics = FirebaseCrashlytics.instance;
      await crashlytics.setCrashlyticsCollectionEnabled(!kDebugMode);
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        unawaited(crashlytics.recordFlutterFatalError(details));
      };
      PlatformDispatcher.instance.onError = (error, stack) {
        unawaited(crashlytics.recordError(error, stack, fatal: true));
        return true;
      };
      _ready = true;
    } catch (e) {
      debugPrint('Crash reporting unavailable: $e');
    }
  }

  /// Logs a handled error and, in the app, reports it as non-fatal, e.g. a
  /// reminder that couldn't be scheduled.
  static void record(
    Object error,
    StackTrace? stack, {
    required String reason,
  }) {
    debugPrint('$reason: $error');
    if (!_ready) return;
    unawaited(
      FirebaseCrashlytics.instance
          .recordError(error, stack, reason: reason)
          .catchError((Object e) {
            debugPrint('Error report not sent: $e');
          }),
    );
  }
}
