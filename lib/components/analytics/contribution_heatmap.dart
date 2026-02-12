import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../reminder_service.dart';

class ContributionHeatmap extends StatelessWidget {
  final List<ProductivityDayStats> days;
  final double cellSize;
  final double spacing;
  final bool showWeekdayLabels;

  const ContributionHeatmap({
    super.key,
    required this.days,
    this.cellSize = 12,
    this.spacing = 3,
    this.showWeekdayLabels = true,
  });

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) {
      return const SizedBox.shrink();
    }

    final sorted = [...days]..sort((a, b) => a.day.compareTo(b.day));
    final start = sorted.first.day;
    final end = sorted.last.day;
    final alignedStart = start.subtract(Duration(days: start.weekday - 1));
    final totalCells = end.difference(alignedStart).inDays + 1;
    final columns = (totalCells / 7).ceil();
    final maxCompleted = sorted.fold<int>(
      0,
      (prev, day) => math.max(prev, day.completed),
    );

    final byDay = {
      for (final day in sorted) day.day.millisecondsSinceEpoch: day,
    };

    final grid = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var column = 0; column < columns; column += 1)
            Padding(
              padding: EdgeInsets.only(right: spacing),
              child: Column(
                children: [
                  for (var row = 0; row < 7; row += 1)
                    _buildCell(
                      context: context,
                      day: alignedStart.add(Duration(days: (column * 7) + row)),
                      rangeStart: start,
                      rangeEnd: end,
                      byDay: byDay,
                      maxCompleted: maxCompleted,
                    ),
                ],
              ),
            ),
        ],
      ),
    );

    if (!showWeekdayLabels) {
      return grid;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(right: spacing + 2),
          child: Column(
            children: [
              _weekdayLabel(context, ''),
              _weekdayLabel(context, 'M'),
              _weekdayLabel(context, ''),
              _weekdayLabel(context, 'W'),
              _weekdayLabel(context, ''),
              _weekdayLabel(context, 'F'),
              _weekdayLabel(context, ''),
            ],
          ),
        ),
        Expanded(child: grid),
      ],
    );
  }

  Widget _buildCell({
    required BuildContext context,
    required DateTime day,
    required DateTime rangeStart,
    required DateTime rangeEnd,
    required Map<int, ProductivityDayStats> byDay,
    required int maxCompleted,
  }) {
    final inRange = !day.isBefore(rangeStart) && !day.isAfter(rangeEnd);
    final stats = byDay[day.millisecondsSinceEpoch];

    final color = _cellColor(
      context: context,
      stats: stats,
      inRange: inRange,
      maxCompleted: maxCompleted,
    );

    final labelDate = DateFormat('EEE, MMM d').format(day);
    final tooltip = stats == null
        ? '$labelDate\nNo activity'
        : '$labelDate\nCompleted: ${stats.completed}\nMissed: ${stats.missed}\nSnoozed: ${stats.snoozed}';

    return Padding(
      padding: EdgeInsets.only(bottom: spacing),
      child: Tooltip(
        message: tooltip,
        child: Container(
          width: cellSize,
          height: cellSize,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
    );
  }

  Widget _weekdayLabel(BuildContext context, String text) {
    return SizedBox(
      width: 14,
      height: cellSize + spacing,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(fontSize: 9, height: 1.0),
        ),
      ),
    );
  }

  Color _cellColor({
    required BuildContext context,
    required ProductivityDayStats? stats,
    required bool inRange,
    required int maxCompleted,
  }) {
    final cs = Theme.of(context).colorScheme;
    if (!inRange) {
      return cs.surfaceContainerHighest.withValues(alpha: 0.25);
    }
    if (stats == null || stats.completed <= 0) {
      return cs.surfaceContainerHighest;
    }
    if (maxCompleted <= 1) {
      return cs.primary.withValues(alpha: 0.9);
    }
    final ratio = (stats.completed / maxCompleted).clamp(0.0, 1.0);
    if (ratio < 0.25) return cs.primary.withValues(alpha: 0.35);
    if (ratio < 0.5) return cs.primary.withValues(alpha: 0.55);
    if (ratio < 0.75) return cs.primary.withValues(alpha: 0.75);
    return cs.primary.withValues(alpha: 0.95);
  }
}

class RecentTrendChart extends StatelessWidget {
  final List<ProductivityDayStats> days;
  final double height;

  const RecentTrendChart({super.key, required this.days, this.height = 120});

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) {
      return const SizedBox.shrink();
    }
    final maxTracked = days.fold<int>(
      1,
      (prev, day) => math.max(prev, day.trackedCount + day.snoozed),
    );
    final cs = Theme.of(context).colorScheme;

    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final day in days)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final barSpace = constraints.maxHeight;
                          final total = day.trackedCount + day.snoozed;
                          final scale = total <= 0 ? 0.0 : total / maxTracked;
                          final barHeight = barSpace * scale;
                          final completedFlex = day.completed;
                          final missedFlex = day.missed;
                          final snoozedFlex = day.snoozed;
                          final denominator =
                              completedFlex + missedFlex + snoozedFlex;

                          return Align(
                            alignment: Alignment.bottomCenter,
                            child: Container(
                              width: double.infinity,
                              height: barHeight,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(6),
                                color: cs.surfaceContainerHighest,
                              ),
                              clipBehavior: Clip.hardEdge,
                              child: denominator == 0
                                  ? const SizedBox.shrink()
                                  : Column(
                                      children: [
                                        if (completedFlex > 0)
                                          Expanded(
                                            flex: completedFlex,
                                            child: Container(color: cs.primary),
                                          ),
                                        if (missedFlex > 0)
                                          Expanded(
                                            flex: missedFlex,
                                            child: Container(color: cs.error),
                                          ),
                                        if (snoozedFlex > 0)
                                          Expanded(
                                            flex: snoozedFlex,
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
                      DateFormat('E').format(day.day).substring(0, 1),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
