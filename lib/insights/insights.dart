/// Completion stats, streaks and insights for the Analytics tab (off in v1;
/// see Features.analytics). Pure functions of the reminders and their events.
library;

import '../date_math.dart';
import '../reminder_model.dart';

class ReminderAnalytics {
  final double weeklyCompletionRate;
  final double monthlyCompletionRate;
  final String? mostMissedReminderId;
  final Map<String, double> timeOfDayPerformance;
  final int longestStreak;

  const ReminderAnalytics({
    required this.weeklyCompletionRate,
    required this.monthlyCompletionRate,
    required this.mostMissedReminderId,
    required this.timeOfDayPerformance,
    required this.longestStreak,
  });
}

class TimeSlotPerformance {
  final String label;
  final int completed;
  final int total;

  const TimeSlotPerformance({
    required this.label,
    required this.completed,
    required this.total,
  });

  double get rate => total == 0 ? 0 : completed / total;
}

class ReminderRiskStat {
  final String reminderId;
  final int completedCount;
  final int missedCount;
  final int snoozedCount;

  const ReminderRiskStat({
    required this.reminderId,
    required this.completedCount,
    required this.missedCount,
    required this.snoozedCount,
  });

  int get trackedCount => completedCount + missedCount;
  double get completionRate =>
      trackedCount == 0 ? 0 : completedCount / trackedCount;
  int get riskScore => (missedCount * 2) + snoozedCount;
}

class ProductivityDayStats {
  final DateTime day;
  final int completed;
  final int missed;
  final int snoozed;

  const ProductivityDayStats({
    required this.day,
    required this.completed,
    required this.missed,
    required this.snoozed,
  });

  int get trackedCount => completed + missed;
  double get completionRate => trackedCount == 0 ? 0 : completed / trackedCount;
}

class ProductivityInsights {
  final ReminderAnalytics summary;
  final int productivityScore;
  final int currentDayStreak;
  final int bestDayStreak;
  final int completedToday;
  final int missedToday;
  final int snoozedToday;
  final int dueToday;
  final int pendingToday;
  final double weeklySnoozePerCompletion;
  final String? bestFocusLabel;
  final List<TimeSlotPerformance> slotPerformance;
  final List<ProductivityDayStats> contributionDays;
  final List<ProductivityDayStats> recentDays;
  final List<ReminderRiskStat> atRiskReminders;
  final List<ReminderRiskStat> topPerformers;

  const ProductivityInsights({
    required this.summary,
    required this.productivityScore,
    required this.currentDayStreak,
    required this.bestDayStreak,
    required this.completedToday,
    required this.missedToday,
    required this.snoozedToday,
    required this.dueToday,
    required this.pendingToday,
    required this.weeklySnoozePerCompletion,
    required this.bestFocusLabel,
    required this.slotPerformance,
    required this.contributionDays,
    required this.recentDays,
    required this.atRiskReminders,
    required this.topPerformers,
  });
}

ReminderAnalytics buildAnalytics({
  required List<ReminderModel> reminders,
  required List<ReminderEvent> events,
}) {
  double completionRate(Duration window) {
    final now = DateTime.now();
    final from = now.subtract(window);
    var complete = 0;
    var miss = 0;
    for (final e in events) {
      if (e.occurredAt.isBefore(from)) continue;
      if (e.type == ReminderEventType.completed) complete += 1;
      if (e.type == ReminderEventType.missed) miss += 1;
    }
    final denom = complete + miss;
    if (denom == 0) return 0;
    return complete / denom;
  }

  final missesByReminder = <String, int>{};
  for (final e in events) {
    if (e.type != ReminderEventType.missed) continue;
    missesByReminder[e.reminderId] = (missesByReminder[e.reminderId] ?? 0) + 1;
  }
  String? mostMissedId;
  var mostMissed = 0;
  missesByReminder.forEach((id, count) {
    if (count > mostMissed) {
      mostMissed = count;
      mostMissedId = id;
    }
  });

  final slots = <String, List<int>>{
    'Morning': [0, 0],
    'Afternoon': [0, 0],
    'Evening': [0, 0],
    'Night': [0, 0],
  };

  for (final e in events) {
    if (e.type != ReminderEventType.completed &&
        e.type != ReminderEventType.missed) {
      continue;
    }
    final hour = e.scheduledAt.hour;
    final key = hour >= 5 && hour < 12
        ? 'Morning'
        : hour >= 12 && hour < 17
        ? 'Afternoon'
        : hour >= 17 && hour < 22
        ? 'Evening'
        : 'Night';
    final bucket = slots[key]!;
    bucket[1] += 1;
    if (e.type == ReminderEventType.completed) bucket[0] += 1;
  }

  final performance = <String, double>{};
  for (final entry in slots.entries) {
    final complete = entry.value[0];
    final total = entry.value[1];
    performance[entry.key] = total == 0 ? 0 : complete / total;
  }

  var longestStreak = 0;
  for (final reminder in reminders) {
    if (reminder.longestStreak > longestStreak) {
      longestStreak = reminder.longestStreak;
    }
  }

  return ReminderAnalytics(
    weeklyCompletionRate: completionRate(const Duration(days: 7)),
    monthlyCompletionRate: completionRate(const Duration(days: 30)),
    mostMissedReminderId: mostMissedId,
    timeOfDayPerformance: performance,
    longestStreak: longestStreak,
  );
}

ProductivityInsights buildProductivityInsights({
  required List<ReminderModel> reminders,
  required List<ReminderEvent> events,
  int contributionDays = 84,
}) {
  final summary = buildAnalytics(reminders: reminders, events: events);

  final now = DateTime.now();
  final today = dayOnly(now);
  final dayBuckets = <int, _MutableDayBucket>{};
  final completedDayKeys = <int>{};

  for (final event in events) {
    final day = dayOnly(event.occurredAt);
    final key = day.millisecondsSinceEpoch;
    final bucket = dayBuckets.putIfAbsent(key, () => _MutableDayBucket(day));
    switch (event.type) {
      case ReminderEventType.completed:
        bucket.completed += 1;
        completedDayKeys.add(key);
        break;
      case ReminderEventType.missed:
        bucket.missed += 1;
        break;
      case ReminderEventType.snoozed:
        bucket.snoozed += 1;
        break;
    }
  }

  final safeContributionDays = contributionDays <= 0 ? 84 : contributionDays;
  final contributionStart = addDays(today, -(safeContributionDays - 1));
  final contribution = <ProductivityDayStats>[];
  for (var i = 0; i < safeContributionDays; i += 1) {
    final day = addDays(contributionStart, i);
    final key = day.millisecondsSinceEpoch;
    final bucket = dayBuckets[key];
    contribution.add(
      ProductivityDayStats(
        day: day,
        completed: bucket?.completed ?? 0,
        missed: bucket?.missed ?? 0,
        snoozed: bucket?.snoozed ?? 0,
      ),
    );
  }

  final recentCount = contribution.length < 14 ? contribution.length : 14;
  final recentDays = contribution
      .skip(contribution.length - recentCount)
      .toList(growable: false);

  final completedToday =
      dayBuckets[today.millisecondsSinceEpoch]?.completed ?? 0;
  final missedToday = dayBuckets[today.millisecondsSinceEpoch]?.missed ?? 0;
  final snoozedToday = dayBuckets[today.millisecondsSinceEpoch]?.snoozed ?? 0;
  final pendingToday = reminders
      .where((r) => r.isActive && dayOnly(r.dueAt) == today)
      .length;
  final dueToday = completedToday + missedToday + pendingToday;

  final currentDayStreak = _computeCurrentDayStreak(
    today: today,
    completedDayKeys: completedDayKeys,
  );
  final bestDayStreak = _computeBestDayStreak(completedDayKeys);

  final weekFrom = now.subtract(const Duration(days: 7));
  var weekCompleted = 0;
  var weekSnoozed = 0;
  for (final event in events) {
    if (event.occurredAt.isBefore(weekFrom)) continue;
    if (event.type == ReminderEventType.completed) weekCompleted += 1;
    if (event.type == ReminderEventType.snoozed) weekSnoozed += 1;
  }
  final double weeklySnoozePerCompletion = weekCompleted == 0
      ? (weekSnoozed > 0 ? weekSnoozed.toDouble() : 0.0)
      : weekSnoozed / weekCompleted.toDouble();

  final slotCounters = <String, List<int>>{
    'Morning': [0, 0],
    'Afternoon': [0, 0],
    'Evening': [0, 0],
    'Night': [0, 0],
  };
  for (final event in events) {
    if (event.type != ReminderEventType.completed &&
        event.type != ReminderEventType.missed) {
      continue;
    }
    final key = _timeSlotForHour(event.scheduledAt.hour);
    final bucket = slotCounters[key]!;
    bucket[1] += 1;
    if (event.type == ReminderEventType.completed) {
      bucket[0] += 1;
    }
  }
  final slotPerformance = slotCounters.entries
      .map(
        (entry) => TimeSlotPerformance(
          label: entry.key,
          completed: entry.value[0],
          total: entry.value[1],
        ),
      )
      .toList(growable: false);

  String? bestFocusLabel;
  final eligibleSlots = slotPerformance.where((s) => s.total >= 3).toList();
  if (eligibleSlots.isNotEmpty) {
    eligibleSlots.sort((a, b) {
      final byRate = b.rate.compareTo(a.rate);
      if (byRate != 0) return byRate;
      return b.total.compareTo(a.total);
    });
    bestFocusLabel = eligibleSlots.first.label;
  }

  final monthFrom = now.subtract(const Duration(days: 30));
  final byReminder = <String, _ReminderAggregate>{};
  for (final event in events) {
    if (event.occurredAt.isBefore(monthFrom)) continue;
    final agg = byReminder.putIfAbsent(
      event.reminderId,
      () => _ReminderAggregate(event.reminderId),
    );
    switch (event.type) {
      case ReminderEventType.completed:
        agg.completed += 1;
        break;
      case ReminderEventType.missed:
        agg.missed += 1;
        break;
      case ReminderEventType.snoozed:
        agg.snoozed += 1;
        break;
    }
  }

  final riskStats = byReminder.values
      .where((a) => a.missed > 0 || a.snoozed > 0)
      .map(
        (a) => ReminderRiskStat(
          reminderId: a.reminderId,
          completedCount: a.completed,
          missedCount: a.missed,
          snoozedCount: a.snoozed,
        ),
      )
      .toList();
  riskStats.sort((a, b) {
    final byScore = b.riskScore.compareTo(a.riskScore);
    if (byScore != 0) return byScore;
    final byMissed = b.missedCount.compareTo(a.missedCount);
    if (byMissed != 0) return byMissed;
    return b.snoozedCount.compareTo(a.snoozedCount);
  });
  final atRiskReminders = riskStats.take(5).toList(growable: false);

  final performerStats = byReminder.values
      .where((a) => (a.completed + a.missed) >= 4)
      .map(
        (a) => ReminderRiskStat(
          reminderId: a.reminderId,
          completedCount: a.completed,
          missedCount: a.missed,
          snoozedCount: a.snoozed,
        ),
      )
      .toList();
  performerStats.sort((a, b) {
    final byRate = b.completionRate.compareTo(a.completionRate);
    if (byRate != 0) return byRate;
    return b.trackedCount.compareTo(a.trackedCount);
  });
  final topPerformers = performerStats.take(5).toList(growable: false);

  final streakScore = (currentDayStreak / 14).clamp(0, 1).toDouble();
  final snoozePenalty = (weeklySnoozePerCompletion / 2).clamp(0, 1).toDouble();
  final snoozeControl = 1 - snoozePenalty;
  final productivityScore =
      ((summary.weeklyCompletionRate * 45) +
              (summary.monthlyCompletionRate * 25) +
              (streakScore * 15) +
              (snoozeControl * 15))
          .round()
          .clamp(0, 100);

  return ProductivityInsights(
    summary: summary,
    productivityScore: productivityScore,
    currentDayStreak: currentDayStreak,
    bestDayStreak: bestDayStreak,
    completedToday: completedToday,
    missedToday: missedToday,
    snoozedToday: snoozedToday,
    dueToday: dueToday,
    pendingToday: pendingToday,
    weeklySnoozePerCompletion: weeklySnoozePerCompletion,
    bestFocusLabel: bestFocusLabel,
    slotPerformance: slotPerformance,
    contributionDays: contribution,
    recentDays: recentDays,
    atRiskReminders: atRiskReminders,
    topPerformers: topPerformers,
  );
}

int _computeCurrentDayStreak({
  required DateTime today,
  required Set<int> completedDayKeys,
}) {
  var streak = 0;
  var cursor = today;
  while (completedDayKeys.contains(cursor.millisecondsSinceEpoch)) {
    streak += 1;
    cursor = addDays(cursor, -1);
  }
  return streak;
}

int _computeBestDayStreak(Set<int> completedDayKeys) {
  if (completedDayKeys.isEmpty) return 0;
  final ordered = completedDayKeys.toList()..sort();
  var best = 1;
  var current = 1;
  for (var i = 1; i < ordered.length; i += 1) {
    final prev = DateTime.fromMillisecondsSinceEpoch(ordered[i - 1]);
    final cur = DateTime.fromMillisecondsSinceEpoch(ordered[i]);
    if (dayOnly(cur) == dayOnly(addDays(prev, 1))) {
      current += 1;
    } else {
      current = 1;
    }
    if (current > best) best = current;
  }
  return best;
}

String _timeSlotForHour(int hour) {
  if (hour >= 5 && hour < 12) return 'Morning';
  if (hour >= 12 && hour < 17) return 'Afternoon';
  if (hour >= 17 && hour < 22) return 'Evening';
  return 'Night';
}

class _MutableDayBucket {
  final DateTime day;
  int completed = 0;
  int missed = 0;
  int snoozed = 0;

  _MutableDayBucket(this.day);
}

class _ReminderAggregate {
  final String reminderId;
  int completed = 0;
  int missed = 0;
  int snoozed = 0;

  _ReminderAggregate(this.reminderId);
}
