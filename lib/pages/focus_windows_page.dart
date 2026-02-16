import 'package:flutter/material.dart';

import '../app_services.dart';
import '../components/common/app_loading.dart';
import '../components/common/app_ui.dart';
import '../reminder_model.dart';
import '../reminder_service.dart';

class FocusWindowsPage extends StatelessWidget {
  const FocusWindowsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Focus Windows')),
      body: StreamBuilder<List<ReminderEvent>>(
        stream: AppServices.reminders.watchEvents(),
        builder: (context, _) {
          return FutureBuilder<ProductivityInsights>(
            future: AppServices.reminders.computeProductivityInsights(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const AppLoadingIndicator(
                  label: 'Calculating focus windows...',
                );
              }

              final insights = snap.data!;
              final best = insights.bestFocusLabel;

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _Hero(bestFocus: best, insights: insights),
                  const SizedBox(height: 14),
                  ...insights.slotPerformance.map(
                    (slot) => AppSurfaceCard(
                      margin: const EdgeInsets.only(bottom: 10),
                      dense: true,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(slot.label),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              LinearProgressIndicator(
                                value: slot.rate,
                                minHeight: 8,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              const SizedBox(height: 6),
                              Text(_guidanceFor(slot)),
                            ],
                          ),
                        ),
                        trailing: Text(
                          '${(slot.rate * 100).toStringAsFixed(1)}%\n${slot.completed}/${slot.total}',
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  String _guidanceFor(TimeSlotPerformance slot) {
    if (slot.total < 3) {
      return 'Not enough data yet. Keep using this time slot.';
    }
    if (slot.rate >= 0.75) {
      return 'High reliability. Schedule important reminders here.';
    }
    if (slot.rate >= 0.5) {
      return 'Moderate reliability. Use reminders with clear descriptions.';
    }
    return 'Low reliability. Consider moving these reminders to your stronger slots.';
  }
}

class _Hero extends StatelessWidget {
  final String? bestFocus;
  final ProductivityInsights insights;

  const _Hero({required this.bestFocus, required this.insights});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppSurfaceCard(
      color: cs.tertiaryContainer.withValues(alpha: 0.62),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Best Focus Window',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: cs.onTertiaryContainer),
          ),
          const SizedBox(height: 6),
          Text(
            bestFocus ?? 'Not enough data',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: cs.onTertiaryContainer,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Weekly snooze/completion ratio: ${insights.weeklySnoozePerCompletion.toStringAsFixed(2)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: cs.onTertiaryContainer.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }
}
