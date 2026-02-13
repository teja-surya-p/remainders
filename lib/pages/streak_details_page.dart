import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_services.dart';
import '../components/analytics/contribution_heatmap.dart';
import '../components/common/app_loading.dart';
import '../components/common/app_ui.dart';
import '../reminder_model.dart';
import '../reminder_service.dart';

enum TrendRange { week, twoWeeks, month, year }

class StreakDetailsPage extends StatefulWidget {
  const StreakDetailsPage({super.key});

  @override
  State<StreakDetailsPage> createState() => _StreakDetailsPageState();
}

class _StreakDetailsPageState extends State<StreakDetailsPage> {
  TrendRange _range = TrendRange.week;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Streak & Trends')),
      body: StreamBuilder<List<ReminderModel>>(
        stream: AppServices.reminders.watchReminders(),
        initialData: AppServices.reminders.currentReminders,
        builder: (context, reminderSnap) {
          final reminders = reminderSnap.data ?? const <ReminderModel>[];

          return StreamBuilder<List<ReminderEvent>>(
            stream: AppServices.reminders.watchEvents(),
            builder: (context, _) {
              return FutureBuilder<ProductivityInsights>(
                future: AppServices.reminders.computeProductivityInsights(
                  contributionDays: 370,
                ),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const AppLoadingIndicator(
                      label: 'Preparing streak trends...',
                    );
                  }
                  final insights = snap.data!;
                  final trend = _buildTrendPoints(
                    range: _range,
                    days: insights.contributionDays,
                  );
                  final topStreakReminders = [
                    ...reminders,
                  ]..sort((a, b) => b.longestStreak.compareTo(a.longestStreak));
                  final streakLeaders = topStreakReminders
                      .where((r) => r.longestStreak > 0)
                      .take(5)
                      .toList(growable: false);

                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _SummaryCard(
                            title: 'Current day streak',
                            value: '${insights.currentDayStreak}',
                          ),
                          _SummaryCard(
                            title: 'Best day streak',
                            value: '${insights.bestDayStreak}',
                          ),
                          _SummaryCard(
                            title: 'Best reminder streak',
                            value: '${insights.summary.longestStreak}',
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      const AppSectionHeader(
                        title: 'Execution Trend',
                        subtitle: 'Switch between short and long-term views',
                      ),
                      const SizedBox(height: 8),
                      _RangeSelector(
                        selected: _range,
                        onChanged: (next) => setState(() => _range = next),
                      ),
                      const SizedBox(height: 10),
                      AppSurfaceCard(
                        dense: true,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _rangeSubtitle(_range),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 8),
                            _TrendBarChart(points: trend),
                            const SizedBox(height: 10),
                            const _TrendLegend(),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      const AppSectionHeader(
                        title: 'Daily Contribution Map',
                        subtitle: 'Color intensity reflects completions by day',
                      ),
                      const SizedBox(height: 8),
                      ContributionHeatmap(days: insights.contributionDays),
                      const SizedBox(height: 14),
                      AppSectionHeader(
                        title: _range == TrendRange.year
                            ? 'Monthly Interaction Breakdown'
                            : 'Day-by-Day Interaction Breakdown',
                      ),
                      const SizedBox(height: 8),
                      ...trend.reversed.map(
                        (point) => AppSurfaceCard(
                          dense: true,
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(point.labelFull),
                            subtitle: Text(
                              'Completed ${point.completed} • Missed ${point.missed} • Snoozed ${point.snoozed}',
                            ),
                            trailing: Text(_percent(point.completionRate)),
                          ),
                        ),
                      ),
                      if (streakLeaders.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        const AppSectionHeader(
                          title: 'Top Streak Reminders',
                          subtitle: 'Best-performing reminder streaks',
                        ),
                        const SizedBox(height: 8),
                        ...streakLeaders.map(
                          (reminder) => AppSurfaceCard(
                            dense: true,
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(reminder.title),
                              subtitle: Text(
                                'Current: ${reminder.currentStreak} • Longest: ${reminder.longestStreak}',
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  static String _rangeSubtitle(TrendRange range) {
    switch (range) {
      case TrendRange.week:
        return 'Showing the last 7 days.';
      case TrendRange.twoWeeks:
        return 'Showing the last 14 days.';
      case TrendRange.month:
        return 'Showing all days in the current month.';
      case TrendRange.year:
        return 'Showing month-wise totals for the current year.';
    }
  }

  static String _percent(double value) =>
      '${(value * 100).toStringAsFixed(1)}%';
}

List<_TrendPoint> _buildTrendPoints({
  required TrendRange range,
  required List<ProductivityDayStats> days,
}) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final byDay = {
    for (final day in days)
      DateTime(day.day.year, day.day.month, day.day.day).millisecondsSinceEpoch:
          day,
  };

  if (range == TrendRange.week || range == TrendRange.twoWeeks) {
    final count = range == TrendRange.week ? 7 : 14;
    final start = today.subtract(Duration(days: count - 1));
    final points = <_TrendPoint>[];
    for (var i = 0; i < count; i += 1) {
      final day = start.add(Duration(days: i));
      final stat = byDay[day.millisecondsSinceEpoch];
      points.add(
        _TrendPoint(
          labelShort: DateFormat('E').format(day).substring(0, 1),
          labelFull: DateFormat('EEE, MMM d').format(day),
          completed: stat?.completed ?? 0,
          missed: stat?.missed ?? 0,
          snoozed: stat?.snoozed ?? 0,
        ),
      );
    }
    return points;
  }

  if (range == TrendRange.month) {
    final monthStart = DateTime(today.year, today.month, 1);
    final monthEnd = DateTime(today.year, today.month + 1, 0);
    final points = <_TrendPoint>[];
    for (
      var day = monthStart;
      !day.isAfter(monthEnd);
      day = day.add(const Duration(days: 1))
    ) {
      final stat = byDay[day.millisecondsSinceEpoch];
      points.add(
        _TrendPoint(
          labelShort: day.day.toString(),
          labelFull: DateFormat('EEE, MMM d').format(day),
          completed: stat?.completed ?? 0,
          missed: stat?.missed ?? 0,
          snoozed: stat?.snoozed ?? 0,
        ),
      );
    }
    return points;
  }

  final points = <_TrendPoint>[];
  for (var month = 1; month <= 12; month += 1) {
    var completed = 0;
    var missed = 0;
    var snoozed = 0;
    for (final stat in days) {
      if (stat.day.year != today.year || stat.day.month != month) continue;
      completed += stat.completed;
      missed += stat.missed;
      snoozed += stat.snoozed;
    }
    final monthDate = DateTime(today.year, month, 1);
    points.add(
      _TrendPoint(
        labelShort: DateFormat('MMM').format(monthDate).substring(0, 1),
        labelFull: DateFormat('MMMM y').format(monthDate),
        completed: completed,
        missed: missed,
        snoozed: snoozed,
      ),
    );
  }
  return points;
}

class _RangeSelector extends StatelessWidget {
  final TrendRange selected;
  final ValueChanged<TrendRange> onChanged;

  const _RangeSelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<TrendRange>(
      segments: const [
        ButtonSegment(value: TrendRange.week, label: Text('1W')),
        ButtonSegment(value: TrendRange.twoWeeks, label: Text('2W')),
        ButtonSegment(value: TrendRange.month, label: Text('1M')),
        ButtonSegment(value: TrendRange.year, label: Text('1Y')),
      ],
      selected: {selected},
      onSelectionChanged: (values) {
        if (values.isEmpty) return;
        onChanged(values.first);
      },
      showSelectedIcon: false,
    );
  }
}

class _TrendPoint {
  final String labelShort;
  final String labelFull;
  final int completed;
  final int missed;
  final int snoozed;

  const _TrendPoint({
    required this.labelShort,
    required this.labelFull,
    required this.completed,
    required this.missed,
    required this.snoozed,
  });

  int get total => completed + missed + snoozed;
  int get tracked => completed + missed;
  double get completionRate => tracked == 0 ? 0 : completed / tracked;
}

class _TrendBarChart extends StatelessWidget {
  final List<_TrendPoint> points;

  const _TrendBarChart({required this.points});

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const SizedBox.shrink();

    final maxTotal = points.fold<int>(
      1,
      (prev, point) => math.max(prev, point.total),
    );
    final cs = Theme.of(context).colorScheme;
    final compact = points.length > 20;
    final barWidth = compact ? 14.0 : 20.0;

    return SizedBox(
      height: 180,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final point in points)
              Padding(
                padding: EdgeInsets.only(right: compact ? 4 : 6),
                child: Tooltip(
                  message:
                      '${point.labelFull}\nCompleted: ${point.completed}\nMissed: ${point.missed}\nSnoozed: ${point.snoozed}',
                  child: SizedBox(
                    width: barWidth,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final total = point.total;
                              final scale = total == 0 ? 0.0 : total / maxTotal;
                              final barHeight = constraints.maxHeight * scale;

                              return Align(
                                alignment: Alignment.bottomCenter,
                                child: Container(
                                  height: barHeight,
                                  decoration: BoxDecoration(
                                    color: cs.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  clipBehavior: Clip.hardEdge,
                                  child: total == 0
                                      ? const SizedBox.shrink()
                                      : Column(
                                          children: [
                                            if (point.completed > 0)
                                              Expanded(
                                                flex: point.completed,
                                                child: Container(
                                                  color: cs.primary,
                                                ),
                                              ),
                                            if (point.missed > 0)
                                              Expanded(
                                                flex: point.missed,
                                                child: Container(
                                                  color: cs.error,
                                                ),
                                              ),
                                            if (point.snoozed > 0)
                                              Expanded(
                                                flex: point.snoozed,
                                                child: Container(
                                                  color: cs.tertiary,
                                                ),
                                              ),
                                          ],
                                        ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          point.labelShort,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TrendLegend extends StatelessWidget {
  const _TrendLegend();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: [
        _LegendDot(text: 'Completed', color: cs.primary),
        _LegendDot(text: 'Missed', color: cs.error),
        _LegendDot(text: 'Snoozed', color: cs.tertiary),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final String text;
  final Color color;

  const _LegendDot({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(text, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;

  const _SummaryCard({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 170,
      child: AppSurfaceCard(
        dense: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 6),
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}
