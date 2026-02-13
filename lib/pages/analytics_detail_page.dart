import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../components/analytics/contribution_heatmap.dart';
import '../components/common/app_ui.dart';
import '../reminder_model.dart';
import '../reminder_service.dart';
import '../theme/app_tokens.dart';

enum AnalyticsDetailType {
  completion,
  streaks,
  trends,
  timeOfDay,
  missed,
  risk,
  consistency,
  focus,
}

class AnalyticsDetailPage extends StatelessWidget {
  final AnalyticsDetailType detail;
  final ProductivityInsights insights;
  final List<ReminderModel> reminders;

  const AnalyticsDetailPage({
    super.key,
    required this.detail,
    required this.insights,
    required this.reminders,
  });

  @override
  Widget build(BuildContext context) {
    final header = _header(detail);
    final byId = {for (final reminder in reminders) reminder.id: reminder};

    return Scaffold(
      appBar: AppBar(title: Text(header.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          if (detail == AnalyticsDetailType.streaks)
            _StreakSection(insights: insights)
          else if (detail == AnalyticsDetailType.completion)
            _CompletionSection(insights: insights)
          else if (detail == AnalyticsDetailType.trends)
            _TrendSection(insights: insights)
          else if (detail == AnalyticsDetailType.timeOfDay)
            _TimeOfDaySection(insights: insights)
          else if (detail == AnalyticsDetailType.missed)
            _MissedSection(insights: insights, byId: byId)
          else if (detail == AnalyticsDetailType.risk)
            _RiskSection(insights: insights, byId: byId)
          else if (detail == AnalyticsDetailType.consistency)
            _ConsistencySection(insights: insights, byId: byId)
          else if (detail == AnalyticsDetailType.focus)
            _FocusSection(insights: insights),
        ],
      ),
    );
  }
}

class _StreakSection extends StatelessWidget {
  final ProductivityInsights insights;

  const _StreakSection({required this.insights});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                title: 'Current streak',
                value: '${insights.currentDayStreak}d',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MetricCard(
                title: 'Longest streak',
                value: '${insights.bestDayStreak}d',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        AppSurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppSectionHeader(
                title: 'Activity Map',
                subtitle: 'GitHub-style contribution intensity',
              ),
              const SizedBox(height: 10),
              ContributionHeatmap(days: insights.contributionDays),
            ],
          ),
        ),
      ],
    );
  }
}

class _CompletionSection extends StatelessWidget {
  final ProductivityInsights insights;

  const _CompletionSection({required this.insights});

  @override
  Widget build(BuildContext context) {
    final recent = insights.contributionDays.length < 7
        ? insights.contributionDays
        : insights.contributionDays.sublist(
            insights.contributionDays.length - 7,
          );
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                title: 'Weekly rate',
                value: _percent(insights.summary.weeklyCompletionRate),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MetricCard(
                title: 'Monthly rate',
                value: _percent(insights.summary.monthlyCompletionRate),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        AppSurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppSectionHeader(
                title: 'Weekly Breakdown',
                subtitle: 'Completion percentage per day',
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final day in recent)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Column(
                          children: [
                            Text(
                              '${(day.completionRate * 100).round()}%',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                            const SizedBox(height: 3),
                            Container(
                              height: 84,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.secondary,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              alignment: Alignment.bottomCenter,
                              child: Container(
                                width: double.infinity,
                                height:
                                    (84 * day.completionRate.clamp(0.0, 1.0))
                                        .toDouble(),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              DateFormat('E').format(day.day).substring(0, 1),
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TrendSection extends StatelessWidget {
  final ProductivityInsights insights;

  const _TrendSection({required this.insights});

  @override
  Widget build(BuildContext context) {
    final points = insights.recentDays;
    return AppSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionHeader(
            title: '14-Day Completion Trend',
            subtitle: 'Daily completion ratios',
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final point in points)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Container(
                      height: 66 * point.completionRate.clamp(0.1, 1.0),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withValues(
                          alpha:
                              0.35 +
                              (point.completionRate.clamp(0.0, 1.0) * 0.65),
                        ),
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                DateFormat('MMM d').format(points.first.day),
                style: Theme.of(context).textTheme.labelSmall,
              ),
              Text(
                DateFormat('MMM d').format(points.last.day),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TimeOfDaySection extends StatelessWidget {
  final ProductivityInsights insights;

  const _TimeOfDaySection({required this.insights});

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(
            title: 'Performance by Time Slot',
            subtitle:
                'Best slot: ${insights.bestFocusLabel ?? 'Not enough data'}',
          ),
          const SizedBox(height: 10),
          for (final slot in insights.slotPerformance)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(width: 72, child: Text(slot.label)),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: slot.rate,
                        minHeight: 10,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 42,
                    child: Text(
                      '${(slot.rate * 100).round()}%',
                      textAlign: TextAlign.right,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MissedSection extends StatelessWidget {
  final ProductivityInsights insights;
  final Map<String, ReminderModel> byId;

  const _MissedSection({required this.insights, required this.byId});

  @override
  Widget build(BuildContext context) {
    final sorted = [...insights.atRiskReminders]
      ..sort((a, b) => b.missedCount.compareTo(a.missedCount));
    if (sorted.isEmpty) {
      return const AppEmptyState(
        icon: Icons.check_circle_outline_rounded,
        title: 'No frequent misses',
        message: 'Great work. You have no high-miss reminders currently.',
      );
    }

    return Column(
      children: sorted
          .map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppSurfaceCard(
                dense: true,
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.error.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${item.missedCount}',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        byId[item.reminderId]?.title ?? item.reminderId,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _RiskSection extends StatelessWidget {
  final ProductivityInsights insights;
  final Map<String, ReminderModel> byId;

  const _RiskSection({required this.insights, required this.byId});

  @override
  Widget build(BuildContext context) {
    if (insights.atRiskReminders.isEmpty) {
      return const AppEmptyState(
        icon: Icons.shield_rounded,
        title: 'No reminders at risk',
        message: 'No recurring reminders are currently under risk pressure.',
      );
    }

    return Column(
      children: insights.atRiskReminders
          .map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _RiskTile(
                title: byId[item.reminderId]?.title ?? item.reminderId,
                subtitle:
                    'Missed ${item.missedCount} • Snoozed ${item.snoozedCount} • Score ${item.riskScore}',
                color: AppTone.of(context).warning,
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _ConsistencySection extends StatelessWidget {
  final ProductivityInsights insights;
  final Map<String, ReminderModel> byId;

  const _ConsistencySection({required this.insights, required this.byId});

  @override
  Widget build(BuildContext context) {
    if (insights.topPerformers.isEmpty) {
      return const AppEmptyState(
        icon: Icons.emoji_events_outlined,
        title: 'No leaders yet',
        message: 'Complete reminders more consistently to build leaderboards.',
      );
    }

    return Column(
      children: insights.topPerformers
          .map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _RiskTile(
                title: byId[item.reminderId]?.title ?? item.reminderId,
                subtitle:
                    'Completion ${_percent(item.completionRate)} • Events ${item.trackedCount}',
                color: AppTone.of(context).chart2,
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _FocusSection extends StatelessWidget {
  final ProductivityInsights insights;

  const _FocusSection({required this.insights});

  @override
  Widget build(BuildContext context) {
    final sorted = [...insights.slotPerformance]
      ..sort((a, b) {
        final byRate = b.rate.compareTo(a.rate);
        if (byRate != 0) return byRate;
        return b.total.compareTo(a.total);
      });

    return Column(
      children: sorted
          .map(
            (slot) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _RiskTile(
                title: slot.label,
                subtitle:
                    'Completion ${_percent(slot.rate)} • Sample size ${slot.total}',
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _RiskTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color color;

  const _RiskTile({
    required this.title,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      dense: true,
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 1),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;

  const _MetricCard({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

({String title, IconData icon}) _header(AnalyticsDetailType detail) {
  switch (detail) {
    case AnalyticsDetailType.completion:
      return (title: 'Completion Rate', icon: Icons.task_alt_rounded);
    case AnalyticsDetailType.streaks:
      return (title: 'Streaks', icon: Icons.local_fire_department_rounded);
    case AnalyticsDetailType.trends:
      return (title: '14-Day Trend', icon: Icons.trending_up_rounded);
    case AnalyticsDetailType.timeOfDay:
      return (title: 'Time of Day', icon: Icons.schedule_rounded);
    case AnalyticsDetailType.missed:
      return (title: 'Most Missed', icon: Icons.warning_amber_rounded);
    case AnalyticsDetailType.risk:
      return (title: 'Risk Reminders', icon: Icons.visibility_rounded);
    case AnalyticsDetailType.consistency:
      return (title: 'Consistency Leaders', icon: Icons.bar_chart_rounded);
    case AnalyticsDetailType.focus:
      return (title: 'Focus Windows', icon: Icons.bolt_rounded);
  }
}

String _percent(double value) => '${(value * 100).toStringAsFixed(1)}%';
