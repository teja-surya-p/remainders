import 'package:flutter/material.dart';

import '../components/common/app_ui.dart';
import '../theme/app_tokens.dart';

class PlanComparisonPage extends StatelessWidget {
  const PlanComparisonPage({super.key});

  static const List<_ComparisonFeature> _features = [
    _ComparisonFeature(
      feature: 'Active reminders per day',
      freeValue: 'Up to 5',
      proValue: 'Unlimited',
      freeIncluded: true,
    ),
    _ComparisonFeature(
      feature: 'Recurring reminders',
      freeValue: 'Basic daily/weekly',
      proValue: 'Advanced rules and intervals',
      freeIncluded: true,
    ),
    _ComparisonFeature(
      feature: 'Multiple reminders per day',
      freeValue: 'Not available',
      proValue: 'Included',
      freeIncluded: false,
    ),
    _ComparisonFeature(
      feature: 'Date-range recurrence',
      freeValue: 'Not available',
      proValue: 'Included',
      freeIncluded: false,
    ),
    _ComparisonFeature(
      feature: 'Smart scheduling actions',
      freeValue: 'Suggestions only',
      proValue: 'Adjust schedule with confirmation',
      freeIncluded: false,
    ),
    _ComparisonFeature(
      feature: 'Streak tracking',
      freeValue: 'Not available',
      proValue: 'Current, longest, completion rate',
      freeIncluded: false,
    ),
    _ComparisonFeature(
      feature: 'Analytics dashboard',
      freeValue: 'Locked',
      proValue: 'Insights, trends, and performance',
      freeIncluded: false,
    ),
    _ComparisonFeature(
      feature: 'Cloud sync',
      freeValue: 'Local device only',
      proValue: 'Sync across devices',
      freeIncluded: false,
    ),
    _ComparisonFeature(
      feature: 'Accountability sharing',
      freeValue: 'View existing shares only',
      proValue: 'Create and join shared reminders',
      freeIncluded: false,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Free vs Pro')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _HeaderCard(),
          const SizedBox(height: 12),
          const _MatrixHeader(),
          const SizedBox(height: 8),
          ..._features.map(
            (feature) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _FeatureMatrixRow(feature: feature),
            ),
          ),
          const SizedBox(height: 12),
          const _FootnoteCard(),
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
            'Each row shows availability with check/cross for Free and Pro.',
      ),
    );
  }
}

class _MatrixHeader extends StatelessWidget {
  const _MatrixHeader();

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      dense: true,
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(
              'Feature',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          Expanded(
            flex: 3,
            child: Center(
              child: Text(
                'Free',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Center(
              child: Text(
                'Pro',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureMatrixRow extends StatelessWidget {
  final _ComparisonFeature feature;

  const _FeatureMatrixRow({required this.feature});

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              feature.feature,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: _PlanAvailabilityCell(
              included: feature.freeIncluded,
              detail: feature.freeValue,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: _PlanAvailabilityCell(
              included: true,
              detail: feature.proValue,
              highlight: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanAvailabilityCell extends StatelessWidget {
  final bool included;
  final String detail;
  final bool highlight;

  const _PlanAvailabilityCell({
    required this.included,
    required this.detail,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tone = AppTone.of(context);
    final statusColor = included
        ? (highlight ? cs.primary : tone.success)
        : cs.error;
    final bgColor = included
        ? statusColor.withValues(alpha: highlight ? 0.16 : 0.12)
        : cs.error.withValues(alpha: 0.12);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withValues(alpha: 0.25)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            included ? Icons.check_circle_rounded : Icons.cancel_rounded,
            color: statusColor,
            size: 20,
          ),
          const SizedBox(height: 6),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: highlight ? cs.onSurface : null,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ComparisonFeature {
  final String feature;
  final String freeValue;
  final String proValue;
  final bool freeIncluded;

  const _ComparisonFeature({
    required this.feature,
    required this.freeValue,
    required this.proValue,
    required this.freeIncluded,
  });
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
