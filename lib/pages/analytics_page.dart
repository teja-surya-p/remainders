import 'package:flutter/material.dart';

import '../app_services.dart';
import '../components/common/app_loading.dart';
import '../components/common/app_ui.dart';
import '../reminder_model.dart';
import '../reminder_service.dart';
import 'consistency_leaders_page.dart';
import 'focus_windows_page.dart';
import 'risk_reminders_page.dart';
import 'streak_details_page.dart';

class AnalyticsPage extends StatelessWidget {
  final VoidCallback onOpenSubscription;

  const AnalyticsPage({super.key, required this.onOpenSubscription});

  @override
  Widget build(BuildContext context) {
    if (!AppServices.reminders.isPremiumMode) {
      return AppLockState(
        title: 'Analytics is a Premium feature',
        message:
            'Unlock streak trends, risk insights, and deep productivity breakdowns.',
        buttonLabel: 'Open Subscription',
        onTap: onOpenSubscription,
      );
    }

    return StreamBuilder<List<ReminderModel>>(
      stream: AppServices.reminders.watchReminders(),
      initialData: AppServices.reminders.currentReminders,
      builder: (context, reminderSnap) {
        final reminders = reminderSnap.data ?? const <ReminderModel>[];
        final byId = {for (final reminder in reminders) reminder.id: reminder};

        return StreamBuilder<List<ReminderEvent>>(
          stream: AppServices.reminders.watchEvents(),
          builder: (context, _) {
            return FutureBuilder<ProductivityInsights>(
              future: AppServices.reminders.computeProductivityInsights(),
              builder: (context, insightsSnap) {
                if (!insightsSnap.hasData) {
                  return const AppLoadingIndicator(
                    label: 'Building your analytics...',
                  );
                }

                final insights = insightsSnap.data!;
                final mostMissedTitle =
                    insights.summary.mostMissedReminderId == null
                    ? 'None'
                    : (byId[insights.summary.mostMissedReminderId!]?.title ??
                          insights.summary.mostMissedReminderId!);

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _HubHero(insights: insights),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _MiniStat(
                          label: 'Weekly',
                          value: _percent(
                            insights.summary.weeklyCompletionRate,
                          ),
                        ),
                        _MiniStat(
                          label: 'Monthly',
                          value: _percent(
                            insights.summary.monthlyCompletionRate,
                          ),
                        ),
                        _MiniStat(
                          label: 'Today',
                          value:
                              '${insights.completedToday}/${insights.dueToday == 0 ? insights.completedToday : insights.dueToday}',
                        ),
                        _MiniStat(
                          label: 'Streak',
                          value: '${insights.currentDayStreak} d',
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    const AppSectionHeader(
                      title: 'Explore Insights',
                      subtitle: 'Open detailed views for each analytics domain',
                    ),
                    const SizedBox(height: 8),
                    _SectionCard(
                      icon: Icons.trending_up,
                      title: 'Streak & Trends',
                      subtitle:
                          'Daily/weekly/monthly/yearly trend view and contribution map.',
                      trailingText: '${insights.currentDayStreak}d streak',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const StreakDetailsPage(),
                          ),
                        );
                      },
                    ),
                    _SectionCard(
                      icon: Icons.schedule,
                      title: 'Focus Windows',
                      subtitle:
                          'See where you perform best by time of day and improve weak slots.',
                      trailingText:
                          insights.bestFocusLabel ?? 'No best slot yet',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const FocusWindowsPage(),
                          ),
                        );
                      },
                    ),
                    _SectionCard(
                      icon: Icons.warning_amber,
                      title: 'Risk Alerts',
                      subtitle:
                          'Find reminders with highest miss/snooze pressure.',
                      trailingText:
                          '${insights.atRiskReminders.length} flagged',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const RiskRemindersPage(),
                          ),
                        );
                      },
                    ),
                    _SectionCard(
                      icon: Icons.emoji_events,
                      title: 'Consistency Leaders',
                      subtitle:
                          'Top reminders by completion reliability over recent outcomes.',
                      trailingText:
                          '${insights.topPerformers.length} ranked • Missed: $mostMissedTitle',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ConsistencyLeadersPage(),
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
      },
    );
  }

  static String _percent(double value) =>
      '${(value * 100).toStringAsFixed(1)}%';
}

class _HubHero extends StatelessWidget {
  final ProductivityInsights insights;

  const _HubHero({required this.insights});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final score = insights.productivityScore;
    final due = insights.dueToday;
    final done = insights.completedToday;
    final todayProgress = due == 0 ? 0.0 : (done / due).clamp(0.0, 1.0);

    return AppSurfaceCard(
      color: cs.secondaryContainer.withValues(alpha: 0.72),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Productivity Score',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: cs.onSecondaryContainer),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                '$score',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: cs.onSecondaryContainer,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '/100',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: cs.onSecondaryContainer.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: todayProgress,
            minHeight: 8,
            borderRadius: BorderRadius.circular(999),
          ),
          const SizedBox(height: 8),
          Text(
            due == 0
                ? 'No due reminders today.'
                : '$done of $due completed today',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: cs.onSecondaryContainer.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;

  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      dense: true,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 6),
          Text(value, style: Theme.of(context).textTheme.labelLarge),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String trailingText;
  final VoidCallback onTap;

  const _SectionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailingText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      margin: const EdgeInsets.only(bottom: 10),
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 6),
                Text(
                  trailingText,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}
