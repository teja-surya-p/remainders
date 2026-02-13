import 'package:flutter/material.dart';

import '../components/common/app_ui.dart';

class PlanComparisonPage extends StatelessWidget {
  const PlanComparisonPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Free vs Pro')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          _HeaderCard(),
          SizedBox(height: 12),
          _FeatureRow(
            feature: 'Active reminders per day',
            freeValue: 'Up to 5',
            proValue: 'Unlimited',
          ),
          _FeatureRow(
            feature: 'Recurring reminders',
            freeValue: 'Basic daily/weekly',
            proValue:
                'Advanced rules, intervals, multiple times/day, date range',
          ),
          _FeatureRow(
            feature: 'Smart scheduling',
            freeValue: 'Suggestions visible, action locked',
            proValue: 'Auto-adjust with confirmation',
          ),
          _FeatureRow(
            feature: 'Streak tracking',
            freeValue: 'Not available',
            proValue: 'Current/longest streak, completion rate, recovery',
          ),
          _FeatureRow(
            feature: 'Analytics dashboard',
            freeValue: 'Locked',
            proValue: 'Weekly/monthly rate, missed trends, time performance',
          ),
          _FeatureRow(
            feature: 'Cloud sync',
            freeValue: 'Local device only',
            proValue: 'Firebase cloud sync across devices',
          ),
          _FeatureRow(
            feature: 'Accountability sharing',
            freeValue: 'View-only for existing shares',
            proValue: 'Create/join shared reminders',
          ),
          SizedBox(height: 12),
          _FootnoteCard(),
        ],
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard();

  @override
  Widget build(BuildContext context) {
    return const AppSurfaceCard(
      child: AppSectionHeader(
        title: 'Plan Comparison',
        subtitle:
            'Compare what is included in Free and Pro before you subscribe.',
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final String feature;
  final String freeValue;
  final String proValue;

  const _FeatureRow({
    required this.feature,
    required this.freeValue,
    required this.proValue,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppSurfaceCard(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(feature, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Free',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(freeValue),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pro',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: cs.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        proValue,
                        style: TextStyle(color: cs.onPrimaryContainer),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FootnoteCard extends StatelessWidget {
  const _FootnoteCard();

  @override
  Widget build(BuildContext context) {
    return AppInlineMessage(
      text:
          'Premium access is controlled by the active pro_access entitlement. '
          'When Premium expires, premium features are locked and data is preserved.',
      icon: Icons.info_outline,
      color: Theme.of(context).colorScheme.secondary,
    );
  }
}
