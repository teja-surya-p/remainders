import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_services.dart';
import '../components/common/app_loading.dart';
import '../components/common/app_ui.dart';
import '../components/reminders/reminder_editor_dialog.dart';
import '../components/reminders/reminder_tile.dart';
import '../reminder_model.dart';
import '../reminder_service.dart';
import 'analytics_page.dart';
import 'calendar_page.dart';
import 'profile_page.dart';
import 'sharing_page.dart';
import 'subscription_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tabIndex = 0;

  void _openSubscriptionTab() {
    if (!mounted) return;
    setState(() => _tabIndex = 4);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _ReminderListTab(onOpenSubscription: _openSubscriptionTab),
      CalendarPage(onOpenSubscription: _openSubscriptionTab),
      AnalyticsPage(onOpenSubscription: _openSubscriptionTab),
      SharingPage(onOpenSubscription: _openSubscriptionTab),
      SubscriptionPage(subscription: AppServices.subscription, asTab: true),
    ];

    final titles = [
      'Reminders',
      'Calendar',
      'Analytics',
      'Sharing',
      'Subscription',
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_tabIndex]),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const ProfilePage()));
            },
            icon: const Icon(Icons.person),
            tooltip: 'Profile',
          ),
        ],
      ),
      body: pages[_tabIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (value) {
          setState(() => _tabIndex = value);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.alarm), label: 'Reminders'),
          NavigationDestination(
            icon: Icon(Icons.calendar_month),
            label: 'Calendar',
          ),
          NavigationDestination(
            icon: Icon(Icons.analytics),
            label: 'Analytics',
          ),
          NavigationDestination(icon: Icon(Icons.group), label: 'Sharing'),
          NavigationDestination(
            icon: Icon(Icons.workspace_premium),
            label: 'Pro',
          ),
        ],
      ),
    );
  }
}

class _ReminderListTab extends StatelessWidget {
  final VoidCallback onOpenSubscription;

  const _ReminderListTab({required this.onOpenSubscription});

  DateTime _startOfToday() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    return (await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Delete reminder?'),
            content: const Text('This cannot be undone.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        )) ??
        false;
  }

  Future<void> _createReminder(BuildContext context) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => ReminderEditorDialog(
        titleText: 'New reminder',
        premiumEnabled: AppServices.reminders.isPremiumMode,
        onSave: (draft) async {
          await AppServices.reminders.createReminder(
            title: draft.title,
            description: draft.description,
            dueAt: draft.dueAt,
            recurrence: draft.recurrence,
            alertMode: draft.alertMode,
            priority: draft.priority,
          );
        },
      ),
    );

    if (result == 'premium_required') {
      onOpenSubscription();
      return;
    }

    if (result == 'created' && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Reminder added')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ReminderModel>>(
      stream: AppServices.reminders.watchReminders(),
      initialData: AppServices.reminders.currentReminders,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const AppLoadingIndicator(label: 'Loading reminders...');
        }

        final reminders =
            snap.data!
                .where(
                  (r) => r.dueAt.isAfter(
                    _startOfToday().subtract(const Duration(seconds: 1)),
                  ),
                )
                .toList()
              ..sort((a, b) => a.dueAt.compareTo(b.dueAt));

        final grouped = <DateTime, List<ReminderModel>>{};
        for (final reminder in reminders) {
          final day = dayOnly(reminder.dueAt);
          grouped.putIfAbsent(day, () => []).add(reminder);
        }

        final days = grouped.keys.toList()..sort();

        return Scaffold(
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () async {
              try {
                await _createReminder(context);
              } on PremiumRequiredException catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(e.message)));
                }
                onOpenSubscription();
              }
            },
            icon: const Icon(Icons.add),
            label: const Text('Add Reminder'),
          ),
          body: days.isEmpty
              ? AppEmptyState(
                  icon: Icons.alarm_add_rounded,
                  title: 'No reminders yet',
                  message:
                      'Create your first reminder to start building daily consistency.',
                  ctaLabel: 'Create Reminder',
                  onCta: () {
                    _createReminder(context);
                  },
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: days.length,
                  itemBuilder: (context, index) {
                    final day = days[index];
                    final list = grouped[day]!;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (index > 0) const SizedBox(height: 14),
                        AppSectionHeader(
                          title: DateFormat('EEE, MMM d').format(day),
                          subtitle:
                              '${list.length} reminder${list.length == 1 ? '' : 's'}',
                        ),
                        const SizedBox(height: 8),
                        ...list.map(
                          (reminder) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: ReminderTile(
                              reminder: reminder,
                              onOpenSubscription: onOpenSubscription,
                              onDelete: () async {
                                final ok = await _confirmDelete(context);
                                if (!ok) return;
                                await AppServices.reminders.deleteReminder(
                                  reminder.id,
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
        );
      },
    );
  }
}
