import 'package:firebase_auth/firebase_auth.dart';

import 'reminder_service.dart';
import 'subscription_service.dart';
import 'theme/theme_service.dart';

class AppServices {
  AppServices._();

  static final ThemeService theme = ThemeService();
  static final SubscriptionService subscription = SubscriptionService();
  static final ReminderService reminders = ReminderService(
    subscription: subscription,
  );

  static bool _initialized = false;

  /// Full app start: theme, purchases, and the device's reminders.
  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    await theme.initialize();
    await subscription.initialize();
    await reminders.initialize();
  }

  /// Background isolates (notification actions, the re-arm job) only need the
  /// device's reminders: no theme, no purchases, no account, no network.
  static Future<void> initializeForBackground() => reminders.initialize();

  /// Called when the user signs in (backup on) or out (null). Reminders stay
  /// on the device either way.
  static Future<void> attachAccount(User? user) async {
    if (user == null) {
      await subscription.unbindUser();
    } else {
      await subscription.bindAuthenticatedUser(user);
    }
    await reminders.attachAccount(user);
  }
}
