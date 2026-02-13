import 'package:flutter/material.dart';

const String kLegalSupportEmail = 'suryatejap24@gmail.com';

class TermsPage extends StatelessWidget {
  const TermsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Terms of Service')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          Text(
            'Effective date: [DATE]\\n'
            'Company: [COMPANY_NAME]\\n'
            'Jurisdiction: [JURISDICTION]\\n\\n'
            '1. Service\\n'
            'Snooze provides reminder and productivity tools with free and premium functionality.\\n\\n'
            '2. Accounts\\n'
            'An authenticated account is required for purchases and premium synchronization.\\n\\n'
            '3. Subscriptions\\n'
            'Subscriptions are billed by Apple App Store or Google Play and validated via RevenueCat entitlement pro_access. Premium access remains active only while entitlement is active.\\n\\n'
            '4. Data handling\\n'
            'Reminder content is stored to provide reminders, analytics, streak tracking, sharing, and cross-device sync for premium users.\\n\\n'
            '5. Downgrade policy\\n'
            'If subscription expires, premium features are locked and data is preserved for potential restoration on re-subscribe.\\n\\n'
            '6. Acceptable use\\n'
            'Users must not abuse, reverse engineer, or attempt to bypass subscription controls.\\n\\n'
            '7. Disclaimer\\n'
            'Service is provided as-is to the extent permitted by law.\\n\\n'
            '8. Contact\\n'
            'Support: suryatejap24@gmail.com',
          ),
        ],
      ),
    );
  }
}

class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy Policy')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          Text(
            'Effective date: [DATE]\\n'
            'Company: [COMPANY_NAME]\\n'
            'Jurisdiction: [JURISDICTION]\\n\\n'
            '1. Data we collect\\n'
            'Account identifiers, reminder data, subscription status metadata, and limited diagnostics.\\n\\n'
            '2. Why we process data\\n'
            'To deliver reminders, entitlement gating, premium sync, analytics, streaks, and sharing.\\n\\n'
            '3. Processors\\n'
            'Firebase, RevenueCat, Apple, and Google Play are used as service providers.\\n\\n'
            '4. Data sharing\\n'
            'We do not sell personal data. Shared reminder content is visible only to participants.\\n\\n'
            '5. Retention\\n'
            'Data may be retained to maintain service continuity and restore access when users re-subscribe.\\n\\n'
            '6. Security\\n'
            'Access control is enforced through Firebase authentication and Firestore security rules.\\n\\n'
            '7. Your rights\\n'
            'You can request data access, correction, or deletion by contacting support.\\n\\n'
            '8. Contact\\n'
            'Privacy contact: suryatejap24@gmail.com',
          ),
        ],
      ),
    );
  }
}
