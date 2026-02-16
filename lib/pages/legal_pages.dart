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
            'Effective date: February 13, 2026\\n'
            'Service: Snooze\\n\\n'
            '1. Service Scope\\n'
            'Snooze provides reminders, recurring schedules, analytics, and optional collaboration features.\\n\\n'
            '2. Accounts\\n'
            'You must sign in to use account-linked features including purchases, cloud sync, and sharing. You are responsible for activity under your account.\\n\\n'
            '3. Subscriptions and Billing\\n'
            'Paid plans are billed by Apple App Store or Google Play and validated using RevenueCat entitlement checks. Access to Pro features depends on active entitlement status.\\n\\n'
            '4. Feature Availability\\n'
            'Free and Pro features may differ. If a subscription expires, Pro-only features are locked while previously stored data is preserved when technically feasible.\\n\\n'
            '5. Acceptable Use\\n'
            'You agree not to abuse the service, interfere with platform security, or attempt to bypass subscription enforcement and access controls.\\n\\n'
            '6. Service Changes\\n'
            'We may improve, modify, or discontinue features to maintain quality, security, and platform compliance.\\n\\n'
            '7. Disclaimer and Liability\\n'
            'Snooze is provided on an as-is and as-available basis. To the maximum extent allowed by law, we disclaim warranties and limit liability for indirect or consequential damages.\\n\\n'
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
            'Effective date: February 13, 2026\\n'
            'Service: Snooze\\n\\n'
            '1. Data We Collect\\n'
            'We collect account identifiers, reminder content, recurrence settings, completion/snooze/miss events, sharing metadata, and subscription entitlement state.\\n\\n'
            '2. Why We Use Data\\n'
            'Data is used to schedule reminders, provide analytics and streaks, enforce free/pro feature access, enable cloud sync for eligible users, and support invite sharing.\\n\\n'
            '3. Service Providers\\n'
            'We use Firebase for authentication and cloud data, RevenueCat for subscription entitlement management, and Apple/Google billing platforms for payments.\\n\\n'
            '4. Sharing and Disclosure\\n'
            'We do not sell personal data. Shared reminder data is visible to invited participants in that shared reminder context.\\n\\n'
            '5. Retention\\n'
            'Data is retained to operate the service and preserve user history. On downgrade, premium data may be locked but retained for restoration if the user upgrades again.\\n\\n'
            '6. Security\\n'
            'Access control is enforced using authenticated user IDs and database security rules designed to prevent cross-user access.\\n\\n'
            '7. Your Choices\\n'
            'You can request account/data deletion by emailing support from your account email: suryatejap24@gmail.com.\\n\\n'
            '8. Contact\\n'
            'Privacy contact: suryatejap24@gmail.com',
          ),
        ],
      ),
    );
  }
}
