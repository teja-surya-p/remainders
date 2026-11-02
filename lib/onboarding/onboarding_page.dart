import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../reliability/reliability.dart';
import '../theme/app_tokens.dart';

/// Whether the first-run introduction has been seen.
class OnboardingState {
  OnboardingState._();

  static const String _key = 'onboarding_done_v1';

  static Future<bool> isDone() async =>
      (await SharedPreferences.getInstance()).getBool(_key) ?? false;

  static Future<void> markDone() async =>
      (await SharedPreferences.getInstance()).setBool(_key, true);
}

/// First run: what Snooze does, then the reliability setup.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  bool _setup = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: _setup ? _buildSetup(context) : _buildWelcome()),
    );
  }

  Widget _buildWelcome() {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    const points = [
      (
        Icons.phone_android_rounded,
        'Works without an account. Your '
            'reminders stay on your phone.',
      ),
      (
        Icons.alarm_rounded,
        'Rings at alarm volume, even on silent, until '
            'you answer it.',
      ),
      (
        Icons.snooze_rounded,
        'Snooze or dismiss right from the '
            'notification.',
      ),
      (
        Icons.cloud_done_outlined,
        'Sign in any time to back up and move to '
            'a new phone.',
      ),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cs.primary,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              Icons.notifications_active_rounded,
              color: cs.onPrimary,
              size: 34,
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Snooze',
          style: textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Reminders that ring like an alarm until you answer them.',
          style: textTheme.titleMedium,
        ),
        const SizedBox(height: 28),
        for (final (icon, text) in points)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: cs.primary),
                const SizedBox(width: 14),
                Expanded(child: Text(text, style: textTheme.bodyLarge)),
              ],
            ),
          ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => setState(() => _setup = true),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          child: const Text('Get started'),
        ),
      ],
    );
  }

  Widget _buildSetup(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      children: [
        Text(
          'Make sure alarms ring',
          style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          'Android can delay or silence reminders unless Snooze is allowed '
          'to run them. Check these once:',
          style: textTheme.bodyLarge,
        ),
        const SizedBox(height: 16),
        const ReliabilityList(),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: widget.onDone,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          child: const Text('Done'),
        ),
        const SizedBox(height: 8),
        Text(
          'You can check these again any time in Profile → Alarm reliability.',
          textAlign: TextAlign.center,
          style: textTheme.bodySmall?.copyWith(
            color: AppTone.of(context).mutedText,
          ),
        ),
      ],
    );
  }
}
