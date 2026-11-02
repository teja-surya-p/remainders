/// Features that are built but switched off in v1. Turn one on for a build
/// with `--dart-define`, e.g. `flutter run --dart-define=SNOOZE_PAYWALL=true`.
/// They are compile-time constants, so code behind a switched-off flag is
/// left out of release builds.
abstract final class Features {
  /// Purchases (RevenueCat), the Pro tab and Pro-only limits. Off: the app
  /// is free, every shipped feature is unlocked, and no purchases SDK runs.
  static const bool paywall = bool.fromEnvironment('SNOOZE_PAYWALL');

  /// The Analytics tab (insights, streaks and the consistency leaderboard).
  static const bool analytics = bool.fromEnvironment('SNOOZE_ANALYTICS');

  /// Shared reminders and invites.
  static const bool sharing = bool.fromEnvironment('SNOOZE_SHARING');
}
