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

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    await theme.initialize();
    await subscription.initialize();
  }

  static Future<void> bindUser(User user) async {
    await subscription.bindAuthenticatedUser(user);
    await reminders.bindUser(user);
  }

  static Future<void> unbindUser() async {
    await reminders.unbindUser();
    await subscription.unbindUser();
  }
}
