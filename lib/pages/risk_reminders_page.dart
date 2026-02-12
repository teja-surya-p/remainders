import 'package:flutter/material.dart';

import '../app_services.dart';
import '../components/common/app_loading.dart';
import '../components/common/app_ui.dart';
import '../reminder_model.dart';
import '../reminder_service.dart';

class RiskRemindersPage extends StatelessWidget {
  const RiskRemindersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Risk Alerts')),
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
                      label: 'Scanning at-risk reminders...',
                    );
                  }
                  final insights = snap.data!;
                  final atRisk = insights.atRiskReminders;

                  if (atRisk.isEmpty) {
                    return const AppEmptyState(
                      icon: Icons.verified_rounded,
                      title: 'No reminders flagged',
                      message:
                          'Great momentum. Nothing is currently classified as high risk.',
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: atRisk.length,
                    itemBuilder: (context, index) {
                      final risk = atRisk[index];
                      final title =
                          byId[risk.reminderId]?.title ?? risk.reminderId;
                      return AppSurfaceCard(
                        margin: const EdgeInsets.only(bottom: 10),
                        dense: true,
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(child: Text('${index + 1}')),
                          title: Text(title),
                          subtitle: Text(
                            'Missed: ${risk.missedCount} • Snoozed: ${risk.snoozedCount}\nCompletion: ${(risk.completionRate * 100).toStringAsFixed(1)}%',
                          ),
                          trailing: Text(
                            'Risk\n${risk.riskScore}',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          isThreeLine: true,
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
