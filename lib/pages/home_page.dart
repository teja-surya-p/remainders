import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_services.dart';
import '../components/common/app_loading.dart';
import '../components/common/app_ui.dart';
import '../components/reminders/reminder_editor_dialog.dart';
import '../components/reminders/reminder_tile.dart';
import '../reminder_model.dart';
import '../theme/app_motion.dart';
import '../theme/app_tokens.dart';
import 'alarm_screen.dart';
import 'analytics_page.dart';
import 'calendar_page.dart';
import 'profile_page.dart';
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
    setState(() => _tabIndex = 3);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _ReminderListTab(onOpenSubscription: _openSubscriptionTab),
      CalendarPage(onOpenSubscription: _openSubscriptionTab),
      AnalyticsPage(onOpenSubscription: _openSubscriptionTab),
      SubscriptionPage(subscription: AppServices.subscription, asTab: true),
      ProfilePage(asTab: true, onOpenSubscription: _openSubscriptionTab),
    ];

    return Scaffold(
      body: SafeArea(
        top: false,
        child: Stack(
          children: [
            AnimatedSwitcher(
              duration: AppMotion.page,
              switchInCurve: AppMotion.emphasized,
              switchOutCurve: AppMotion.standard,
              transitionBuilder: (child, animation) {
                final slide = Tween<Offset>(
                  begin: const Offset(0.06, 0),
                  end: Offset.zero,
                ).animate(animation);
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(position: slide, child: child),
                );
              },
              child: KeyedSubtree(
                key: ValueKey(_tabIndex),
                child: pages[_tabIndex],
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 10,
              child: _GlassBottomNav(
                currentIndex: _tabIndex,
                onChanged: (next) => setState(() => _tabIndex = next),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _ReminderFilter { all, active, completed }

class _ReminderListTab extends StatefulWidget {
  final VoidCallback onOpenSubscription;

  const _ReminderListTab({required this.onOpenSubscription});

  @override
  State<_ReminderListTab> createState() => _ReminderListTabState();
}

class _ReminderListTabState extends State<_ReminderListTab> {
  _ReminderFilter _filter = _ReminderFilter.all;
  bool _searchOpen = false;
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

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

  Future<void> _createReminder(
    BuildContext context,
    int activeToday,
    bool isPremium,
  ) async {
    if (!isPremium && activeToday >= 5) {
      widget.onOpenSubscription();
      return;
    }

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
            alarmSoundId: draft.alarmSoundId,
            notificationSoundId: draft.notificationSoundId,
          );
        },
      ),
    );

    if (result == 'premium_required') {
      widget.onOpenSubscription();
      return;
    }

    if (result == 'created' && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Reminder added')));
    }
  }

  Future<void> _openTestAlarm(
    BuildContext context,
    List<ReminderModel> reminders,
  ) async {
    final target = reminders.where((r) {
      return r.isActive &&
          (r.alertMode == ReminderAlertMode.ringOnly ||
              r.alertMode == ReminderAlertMode.ringAndNotify);
    }).firstOrNull;

    if (target == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Create a ring reminder first.')),
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AlarmScreen(reminderId: target.id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tone = AppTone.of(context);

    return StreamBuilder<List<ReminderModel>>(
      stream: AppServices.reminders.watchReminders(),
      initialData: AppServices.reminders.currentReminders,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const AppLoadingIndicator(label: 'Loading reminders...');
        }

        final reminders = snap.data!;
        final now = DateTime.now();
        final today = _dayOnly(now);

        final todayReminders =
            reminders
                .where((r) => _dayOnly(r.dueAt) == today)
                .toList(growable: false)
              ..sort((a, b) => a.dueAt.compareTo(b.dueAt));

        final activeToday = todayReminders.where((r) => r.isActive).length;
        final completedToday = todayReminders
            .where((r) => r.completed && !r.missed)
            .length;

        final query = _search.text.trim().toLowerCase();
        final filtered = todayReminders
            .where((r) {
              if (_filter == _ReminderFilter.active && !r.isActive) {
                return false;
              }
              if (_filter == _ReminderFilter.completed && !r.completed) {
                return false;
              }
              if (query.isNotEmpty) {
                final title = r.title.toLowerCase();
                final desc = (r.description ?? '').toLowerCase();
                if (!title.contains(query) && !desc.contains(query)) {
                  return false;
                }
              }
              return true;
            })
            .toList(growable: false);

        final cloudEnabled = AppServices.subscription.shouldUseCloudSync;
        final isPremium = AppServices.reminders.isPremiumMode;

        return Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 56, 16, 110),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            DateFormat('EEEE, MMM d').format(now),
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(color: tone.mutedText),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _greeting(now),
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                    AppSurfaceCard(
                      dense: true,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            cloudEnabled
                                ? Icons.cloud_done_rounded
                                : Icons.cloud_off_rounded,
                            size: 14,
                            color: cloudEnabled ? tone.success : tone.mutedText,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            cloudEnabled ? 'Synced' : 'Local',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: cloudEnabled
                                      ? tone.success
                                      : tone.mutedText,
                                ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () => _openTestAlarm(context, reminders),
                      tooltip: 'Test alarm',
                      icon: const Icon(Icons.alarm_rounded),
                    ),
                    IconButton(
                      onPressed: () =>
                          setState(() => _searchOpen = !_searchOpen),
                      tooltip: 'Search',
                      icon: Icon(
                        _searchOpen ? Icons.close : Icons.search_rounded,
                      ),
                    ),
                  ],
                ),
                AnimatedSize(
                  duration: AppMotion.card,
                  curve: AppMotion.standard,
                  child: _searchOpen
                      ? Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: TextField(
                            controller: _search,
                            autofocus: true,
                            decoration: const InputDecoration(
                              hintText: 'Search reminders...',
                              prefixIcon: Icon(Icons.search_rounded),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: AppSurfaceCard(
                        child: Row(
                          children: [
                            _StatValue(
                              label: 'Active',
                              value: '$activeToday',
                              color: cs.onSurface,
                            ),
                            _divider(context),
                            _StatValue(
                              label: 'Done',
                              value: '$completedToday',
                              color: tone.success,
                            ),
                            _divider(context),
                            _StatValue(
                              label: 'Total',
                              value: '${todayReminders.length}',
                              color: cs.onSurface,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (!isPremium) ...[
                      const SizedBox(width: 10),
                      AppSurfaceCard(
                        onTap: widget.onOpenSubscription,
                        color: cs.primary.withValues(alpha: 0.08),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                        child: Column(
                          children: [
                            Text(
                              '$activeToday/5',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: cs.primary,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            Text(
                              'Free limit',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: cs.primary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _FilterChip(
                        label: 'All',
                        selected: _filter == _ReminderFilter.all,
                        onTap: () =>
                            setState(() => _filter = _ReminderFilter.all),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _FilterChip(
                        label: 'Active',
                        selected: _filter == _ReminderFilter.active,
                        onTap: () =>
                            setState(() => _filter = _ReminderFilter.active),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _FilterChip(
                        label: 'Completed',
                        selected: _filter == _ReminderFilter.completed,
                        onTap: () =>
                            setState(() => _filter = _ReminderFilter.completed),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (filtered.isEmpty)
                  AppEmptyState(
                    icon: Icons.tune_rounded,
                    title: query.isNotEmpty
                        ? 'No matching reminders'
                        : 'No reminders yet',
                    message: query.isNotEmpty
                        ? 'Try a different keyword.'
                        : 'Tap + to create your first reminder.',
                  )
                else
                  ...filtered.asMap().entries.map((entry) {
                    final index = entry.key;
                    final reminder = entry.value;
                    return TweenAnimationBuilder<double>(
                      key: ValueKey(reminder.id),
                      tween: Tween(begin: 0, end: 1),
                      duration: Duration(milliseconds: 220 + (index * 45)),
                      curve: AppMotion.emphasized,
                      builder: (context, t, child) {
                        return Opacity(
                          opacity: t,
                          child: Transform.translate(
                            offset: Offset(0, 12 * (1 - t)),
                            child: child,
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: ReminderTile(
                          reminder: reminder,
                          onOpenSubscription: widget.onOpenSubscription,
                          onDelete: () async {
                            final ok = await _confirmDelete(context);
                            if (!ok) return;
                            await AppServices.reminders.deleteReminder(
                              reminder.id,
                            );
                          },
                        ),
                      ),
                    );
                  }),
              ],
            ),
            Positioned(
              right: 20,
              bottom: 96,
              child: FilledButton(
                onPressed: () =>
                    _createReminder(context, activeToday, isPremium),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  minimumSize: const Size(56, 56),
                  padding: EdgeInsets.zero,
                ),
                child: const Icon(Icons.add_rounded, size: 28),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _divider(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      width: 1,
      height: 34,
      color: Theme.of(
        context,
      ).colorScheme.outlineVariant.withValues(alpha: 0.7),
    );
  }

  String _greeting(DateTime now) {
    final hour = now.hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }
}

class _StatValue extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatValue({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppTone.of(context).mutedText,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tone = AppTone.of(context);
    return AppSurfaceCard(
      dense: true,
      color: selected ? cs.surface : cs.secondary.withValues(alpha: 0.58),
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            color: selected ? cs.onSurface : tone.mutedText,
          ),
        ),
      ),
    );
  }
}

class _GlassBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onChanged;

  const _GlassBottomNav({required this.currentIndex, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tone = AppTone.of(context);
    const items = <({IconData icon, String label})>[
      (icon: Icons.notifications_active_outlined, label: 'Reminders'),
      (icon: Icons.calendar_month_outlined, label: 'Calendar'),
      (icon: Icons.bar_chart_rounded, label: 'Analytics'),
      (icon: Icons.workspace_premium_outlined, label: 'Pro'),
      (icon: Icons.person_outline_rounded, label: 'Profile'),
    ];

    return AnimatedContainer(
      duration: AppMotion.card,
      curve: AppMotion.standard,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: tone.glassBackground,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: tone.cardBorder.withValues(alpha: 0.7)),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (var i = 0; i < items.length; i++)
            _NavItem(
              icon: items[i].icon,
              label: items[i].label,
              selected: currentIndex == i,
              onTap: () => onChanged(i),
            ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tone = AppTone.of(context);

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSlide(
                duration: AppMotion.micro,
                offset: selected ? const Offset(0, -0.08) : Offset.zero,
                child: Icon(
                  icon,
                  size: 20,
                  color: selected ? cs.primary : tone.mutedText,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: selected ? cs.primary : tone.mutedText,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              AnimatedContainer(
                duration: AppMotion.micro,
                width: selected ? 16 : 0,
                height: 2.2,
                decoration: BoxDecoration(
                  color: cs.primary,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
