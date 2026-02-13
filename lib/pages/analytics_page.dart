import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_services.dart';
import '../components/common/app_loading.dart';
import '../components/common/app_ui.dart';
import '../reminder_model.dart';
import '../reminder_service.dart';
import '../theme/app_tokens.dart';
import 'analytics_detail_page.dart';

class AnalyticsPage extends StatefulWidget {
  final VoidCallback onOpenSubscription;

  const AnalyticsPage({super.key, required this.onOpenSubscription});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

enum _RangeMode { week, twoWeeks, month, year }

class _AnalyticsPageState extends State<AnalyticsPage> {
  _RangeMode _range = _RangeMode.week;

  @override
  Widget build(BuildContext context) {
    if (!AppServices.reminders.isPremiumMode) {
      return AppLockState(
        title: 'Analytics is a Premium feature',
        message:
            'Unlock streak trends, risk insights, and deep productivity breakdowns.',
        buttonLabel: 'Open Subscription',
        onTap: widget.onOpenSubscription,
      );
    }

    return StreamBuilder<List<ReminderModel>>(
      stream: AppServices.reminders.watchReminders(),
      initialData: AppServices.reminders.currentReminders,
      builder: (context, reminderSnap) {
        final reminders = reminderSnap.data ?? const <ReminderModel>[];

        return FutureBuilder<ProductivityInsights>(
          future: AppServices.reminders.computeProductivityInsights(),
          builder: (context, insightsSnap) {
            if (!insightsSnap.hasData) {
              return const AppLoadingIndicator(
                label: 'Building your analytics...',
              );
            }

            final insights = insightsSnap.data!;
            final tone = AppTone.of(context);
            final cs = Theme.of(context).colorScheme;

            final trend = _buildTrendPoints(insights, _range);
            final trendDirection = trend.isEmpty
                ? 'Stable'
                : trend.last.completionRate >= trend.first.completionRate
                ? 'Improving'
                : 'Declining';

            final mostMissed = insights.atRiskReminders.isEmpty
                ? 0
                : insights.atRiskReminders
                      .map((e) => e.missedCount)
                      .fold<int>(0, math.max);

            final cards = <_AnalyticsCardData>[
              _AnalyticsCardData(
                type: AnalyticsDetailType.completion,
                label: 'Completion Rate',
                value: _percent(insights.summary.weeklyCompletionRate),
                subtitle: 'Weekly performance',
                icon: Icons.task_alt_rounded,
                color: tone.chart2,
              ),
              _AnalyticsCardData(
                type: AnalyticsDetailType.streaks,
                label: 'Current Streak',
                value: '${insights.currentDayStreak} days',
                subtitle: 'Longest: ${insights.bestDayStreak} days',
                icon: Icons.local_fire_department_rounded,
                color: cs.primary,
              ),
              _AnalyticsCardData(
                type: AnalyticsDetailType.trends,
                label: '14-Day Trend',
                value: trendDirection,
                subtitle: '${trend.length} points in range',
                icon: Icons.trending_up_rounded,
                color: tone.chart2,
              ),
              _AnalyticsCardData(
                type: AnalyticsDetailType.timeOfDay,
                label: 'Best Time',
                value: insights.bestFocusLabel ?? 'N/A',
                subtitle: 'Highest completion slot',
                icon: Icons.schedule_rounded,
                color: tone.chart3,
              ),
              _AnalyticsCardData(
                type: AnalyticsDetailType.missed,
                label: 'Most Missed',
                value: '$mostMissed misses',
                subtitle: 'Across at-risk reminders',
                icon: Icons.warning_amber_rounded,
                color: cs.error,
              ),
              _AnalyticsCardData(
                type: AnalyticsDetailType.risk,
                label: 'Risk Reminders',
                value: '${insights.atRiskReminders.length} at risk',
                subtitle: 'Frequent snooze/miss patterns',
                icon: Icons.visibility_rounded,
                color: tone.warning,
              ),
              _AnalyticsCardData(
                type: AnalyticsDetailType.consistency,
                label: 'Consistency Leaders',
                value: '${insights.topPerformers.length} ranked',
                subtitle: 'Top reminders by reliability',
                icon: Icons.bar_chart_rounded,
                color: tone.chart3,
              ),
              _AnalyticsCardData(
                type: AnalyticsDetailType.focus,
                label: 'Focus Windows',
                value: insights.bestFocusLabel ?? 'No peak yet',
                subtitle: 'Most productive time window',
                icon: Icons.bolt_rounded,
                color: cs.primary,
              ),
            ];

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 56, 16, 110),
              children: [
                Text(
                  'Analytics',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Your productivity insights',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: tone.mutedText),
                ),
                const SizedBox(height: 10),
                _RangeSelector(
                  selected: _range,
                  onChanged: (next) => setState(() => _range = next),
                ),
                const SizedBox(height: 10),
                _HeroCard(insights: insights),
                const SizedBox(height: 10),
                AppSurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppSectionHeader(
                        title: 'Daily completions',
                        subtitle: _rangeLabel(_range),
                      ),
                      const SizedBox(height: 10),
                      _MiniTrend(points: trend),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Detailed Insights',
                  style: Theme.of(
                    context,
                  ).textTheme.labelMedium?.copyWith(color: tone.mutedText),
                ),
                const SizedBox(height: 6),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: cards.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 1.0,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemBuilder: (context, index) {
                    final card = cards[index];
                    return AppSurfaceCard(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => AnalyticsDetailPage(
                              detail: card.type,
                              insights: insights,
                              reminders: reminders,
                            ),
                          ),
                        );
                      },
                      dense: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: card.color.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                alignment: Alignment.center,
                                child: Icon(
                                  card.icon,
                                  size: 17,
                                  color: card.color,
                                ),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                color: tone.mutedText,
                              ),
                            ],
                          ),
                          const Spacer(),
                          Text(
                            card.label,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: tone.mutedText),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            card.value,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            card.subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: tone.mutedText),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  List<ProductivityDayStats> _buildTrendPoints(
    ProductivityInsights insights,
    _RangeMode range,
  ) {
    final days = insights.contributionDays;
    if (days.isEmpty) return const [];

    switch (range) {
      case _RangeMode.week:
        return days.length <= 7 ? days : days.sublist(days.length - 7);
      case _RangeMode.twoWeeks:
        return days.length <= 14 ? days : days.sublist(days.length - 14);
      case _RangeMode.month:
        final now = DateTime.now();
        return days
            .where((d) => d.day.year == now.year && d.day.month == now.month)
            .toList(growable: false);
      case _RangeMode.year:
        final now = DateTime.now();
        final monthly = <int, List<int>>{};
        for (final day in days) {
          if (day.day.year != now.year) continue;
          final bucket = monthly.putIfAbsent(day.day.month, () => [0, 0, 0]);
          bucket[0] += day.completed;
          bucket[1] += day.missed;
          bucket[2] += day.snoozed;
        }
        final points = <ProductivityDayStats>[];
        for (var m = 1; m <= 12; m += 1) {
          final b = monthly[m] ?? const [0, 0, 0];
          points.add(
            ProductivityDayStats(
              day: DateTime(now.year, m, 1),
              completed: b[0],
              missed: b[1],
              snoozed: b[2],
            ),
          );
        }
        return points;
    }
  }

  static String _percent(double value) =>
      '${(value * 100).toStringAsFixed(1)}%';

  String _rangeLabel(_RangeMode value) {
    switch (value) {
      case _RangeMode.week:
        return '1 week';
      case _RangeMode.twoWeeks:
        return '2 weeks';
      case _RangeMode.month:
        return '1 month';
      case _RangeMode.year:
        return '1 year';
    }
  }
}

class _RangeSelector extends StatelessWidget {
  final _RangeMode selected;
  final ValueChanged<_RangeMode> onChanged;

  const _RangeSelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const items = <(_RangeMode, String)>[
      (_RangeMode.week, '1W'),
      (_RangeMode.twoWeeks, '2W'),
      (_RangeMode.month, '1M'),
      (_RangeMode.year, '1Y'),
    ];

    return Row(
      children: [
        for (final item in items) ...[
          Expanded(
            child: AppSurfaceCard(
              dense: true,
              color: selected == item.$1
                  ? Theme.of(context).colorScheme.surface
                  : Theme.of(
                      context,
                    ).colorScheme.secondary.withValues(alpha: 0.58),
              onTap: () => onChanged(item.$1),
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Center(
                child: Text(
                  item.$2,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: selected == item.$1
                        ? Theme.of(context).colorScheme.onSurface
                        : AppTone.of(context).mutedText,
                  ),
                ),
              ),
            ),
          ),
          if (item != items.last) const SizedBox(width: 6),
        ],
      ],
    );
  }
}

class _HeroCard extends StatelessWidget {
  final ProductivityInsights insights;

  const _HeroCard({required this.insights});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tone = AppTone.of(context);

    return AppSurfaceCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Overall Score',
                  style: Theme.of(
                    context,
                  ).textTheme.labelMedium?.copyWith(color: tone.mutedText),
                ),
                const SizedBox(height: 2),
                Text(
                  '${insights.productivityScore}',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 4,
                  children: [
                    _LegendDot(
                      color: tone.chart2,
                      label: '${insights.completedToday} completed',
                    ),
                    _LegendDot(
                      color: cs.error,
                      label: '${insights.missedToday} missed',
                    ),
                    _LegendDot(
                      color: tone.warning,
                      label: '${insights.snoozedToday} snoozed',
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(
            width: 86,
            height: 86,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 86,
                  height: 86,
                  child: CircularProgressIndicator(
                    value: insights.productivityScore / 100,
                    strokeWidth: 7,
                    backgroundColor: cs.secondary,
                  ),
                ),
                Text(
                  '${insights.productivityScore}',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

class _MiniTrend extends StatelessWidget {
  final List<ProductivityDayStats> points;

  const _MiniTrend({required this.points});

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const SizedBox(height: 80);
    }

    final maxValue = points.fold<int>(
      1,
      (prev, p) => math.max(prev, p.completed + p.missed),
    );

    return SizedBox(
      height: 96,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final point in points)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Container(
                  height: ((point.completed + point.missed) / maxValue * 86)
                      .clamp(8, 86)
                      .toDouble(),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(
                      alpha: point.completionRate >= 0.8
                          ? 0.95
                          : point.completionRate >= 0.5
                          ? 0.62
                          : 0.34,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AnalyticsCardData {
  final AnalyticsDetailType type;
  final String label;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _AnalyticsCardData({
    required this.type,
    required this.label,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });
}
