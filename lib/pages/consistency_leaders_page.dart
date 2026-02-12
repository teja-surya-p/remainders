import 'package:flutter/material.dart';

import '../app_services.dart';
import '../components/common/app_loading.dart';
import '../components/common/app_ui.dart';
import '../reminder_model.dart';
import '../reminder_service.dart';

class ConsistencyLeadersPage extends StatelessWidget {
  const ConsistencyLeadersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Consistency Leaders')),
      body: StreamBuilder<List<ReminderModel>>(
        stream: AppServices.reminders.watchReminders(),
        initialData: AppServices.reminders.currentReminders,
        builder: (context, reminderSnap) {
          final reminders = reminderSnap.data ?? const <ReminderModel>[];
          final byId = {
            for (final reminder in reminders) reminder.id: reminder,
          };

          return StreamBuilder<List<ReminderEvent>>(
            stream: AppServices.reminders.watchEvents(),
            builder: (context, _) {
              return FutureBuilder<ProductivityInsights>(
                future: AppServices.reminders.computeProductivityInsights(),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const AppLoadingIndicator(
                      label: 'Ranking consistency leaders...',
                    );
                  }
                  final insights = snap.data!;
                  final leaders = insights.topPerformers;

                  if (leaders.isEmpty) {
                    return const AppEmptyState(
                      icon: Icons.assessment_outlined,
                      title: 'Not enough ranking data',
                      message:
                          'Keep completing reminders to generate consistency leaderboards.',
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: leaders.length,
                    itemBuilder: (context, index) {
                      final leader = leaders[index];
                      final title =
                          byId[leader.reminderId]?.title ?? leader.reminderId;
                      return AppSurfaceCard(
                        margin: const EdgeInsets.only(bottom: 10),
                        dense: true,
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(child: Text('#${index + 1}')),
                          title: Text(title),
                          subtitle: Text(
                            'Completed ${leader.completedCount} • Missed ${leader.missedCount} • Snoozed ${leader.snoozedCount}',
                          ),
                          trailing: Text(
                            '${(leader.completionRate * 100).toStringAsFixed(1)}%',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
