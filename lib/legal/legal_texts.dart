/// The privacy policy and terms of service, kept as plain data (no Flutter)
/// so the app and the public web pages can be produced from the same text.
library;

const String kLegalSupportEmail = 'suryatejap24@gmail.com';

class LegalSection {
  const LegalSection(this.heading, this.text);

  final String heading;

  /// Paragraphs separated by line breaks; one starting with "• " is a
  /// bullet point.
  final String text;

  List<String> get paragraphs => text.split('\n');
}

class LegalDocument {
  const LegalDocument({
    required this.title,
    required this.effectiveDate,
    required this.sections,
  });

  final String title;
  final String effectiveDate;
  final List<LegalSection> sections;
}

const LegalDocument privacyPolicy = LegalDocument(
  title: 'Privacy Policy',
  effectiveDate: 'November 1, 2026',
  sections: [
    LegalSection(
      'The short version',
      '• Snooze keeps your reminders on your phone. You don’t need an '
          'account to use it.'
          '\n'
          '• If you sign in, Snooze also keeps a backup copy of your reminders '
          'in your account, so you can get them back on a new phone.'
          '\n'
          '• We don’t sell your data, show ads, or use your reminders for '
          'anything except running Snooze.',
    ),
    LegalSection(
      'What stays on your phone',
      'Your reminders (titles, notes, times, repeat settings and sounds), '
          'their history (when you completed, snoozed or missed them) and '
          'your settings are stored in the app’s storage on your phone. '
          'They don’t leave your phone unless you sign in to back up.',
    ),
    LegalSection(
      'If you sign in to back up',
      '• Account: your email address and an account ID. If you sign in with '
          'Google, also your name and profile picture as Google provides '
          'them. Handled by Firebase Authentication (Google).'
          '\n'
          '• Backup: a copy of your reminders and their history, stored in '
          'Cloud Firestore (Google Cloud) under your account ID. It is used '
          'only to restore your reminders and keep them the same on your '
          'phones.',
    ),
    LegalSection(
      'Crash reports',
      'To find and fix bugs, Snooze sends crash reports through Firebase '
          'Crashlytics (Google): what went wrong in the app, your device '
          'model, Android version and the app version. They don’t '
          'include your reminders.',
    ),
    LegalSection(
      'Permissions',
      'Snooze asks to show notifications, to schedule exact alarms, to show '
          'alarms over the lock screen, and to restore alarms after your '
          'phone restarts. These only let reminders ring on time; none of '
          'them sends data anywhere.',
    ),
    LegalSection(
      'Who handles your data',
      'Google, through Firebase, stores the backup and crash reports for us '
          'as our service provider (firebase.google.com/support/privacy). '
          'We don’t share your data with anyone else, and we never sell '
          'it.',
    ),
    LegalSection(
      'How long we keep it',
      '• On your phone: until you delete it or uninstall Snooze.'
          '\n'
          '• Backup: until you delete your account. When you delete a reminder, '
          'its backup copy is replaced by a small marker without its '
          'content, so your other phones delete it too.'
          '\n'
          '• Crash reports: kept by Firebase for 90 days.',
    ),
    LegalSection(
      'Deleting your data',
      '• In the app: Profile → Delete account deletes your account and '
          'your backup right away, and can also remove your reminders from '
          'the phone.'
          '\n'
          '• Signing out stops the backup. Your reminders stay on the phone '
          'unless you choose to remove them.'
          '\n'
          '• Without the app: email $kLegalSupportEmail from your account’s '
          'address, and we’ll delete your account and backup within '
          '30 days.',
    ),
    LegalSection(
      'Security',
      'Backups are encrypted in transit (HTTPS) and stored encrypted by '
          'Google Cloud. Security rules let each account read and write only '
          'its own backup.',
    ),
    LegalSection(
      'Children',
      'Snooze isn’t directed at children under 13, and we don’t '
          'knowingly collect their data.',
    ),
    LegalSection(
      'Changes',
      'If this policy changes, we’ll update the date above and, for '
          'important changes, tell you in the app.',
    ),
    LegalSection('Contact', 'Questions or requests: $kLegalSupportEmail'),
  ],
);

const LegalDocument termsOfService = LegalDocument(
  title: 'Terms of Service',
  effectiveDate: 'November 1, 2026',
  sections: [
    LegalSection(
      'Using Snooze',
      'Snooze is a reminder and alarm app. You can use it without an '
          'account; signing in is optional and only adds a backup.',
    ),
    LegalSection(
      'Reminders can be missed',
      'Snooze works hard to alert you on time, but your phone decides when '
          'apps may run. Battery savers, Do Not Disturb, denied permissions, '
          'a phone that is off or out of battery, and system updates can '
          'delay or block a reminder.'
          '\n'
          'Don’t rely on Snooze alone for anything where a missed reminder '
          'could cause harm, such as critical medication. Follow the setup '
          'steps in the app so your phone lets Snooze ring on time.',
    ),
    LegalSection(
      'Your account',
      'Keep your sign-in details safe. You can delete your account at any '
          'time in Profile.',
    ),
    LegalSection(
      'Your reminders',
      'Your reminders are yours. We use them only to run Snooze, for '
          'example to restore your backup.',
    ),
    LegalSection(
      'Acceptable use',
      'Don’t try to access other people’s data, interfere with the '
          'service, or get around its security.',
    ),
    LegalSection(
      'Changes',
      'We may change or stop features. If the backup is ever shut down, '
          'we’ll tell you in advance; your reminders stay on your '
          'phone.',
    ),
    LegalSection(
      'No warranty',
      'Snooze is provided “as is”. To the extent the law allows, we '
          'make no warranties and aren’t liable for indirect or '
          'consequential losses, including those from a missed reminder.',
    ),
    LegalSection('Contact', 'Questions: $kLegalSupportEmail'),
  ],
);
