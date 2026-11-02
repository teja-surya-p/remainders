import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_services.dart';
import '../components/common/app_loading.dart';
import '../components/common/app_ui.dart';
import '../components/permissions/alarm_permission_prompt.dart';
import '../components/reminders/reminder_editor_dialog.dart';
import '../components/reminders/reminder_tile.dart';
import '../date_math.dart';
import '../features.dart';
import '../reminder_model.dart';
import '../theme/app_motion.dart';
import '../theme/app_tokens.dart';
import 'alarm_screen.dart';
import 'analytics_page.dart';
import 'calendar_page.dart';
import 'profile_page.dart';
import 'subscription_page.dart';

typedef _Tab = ({IconData icon, String label, Widget page});

/// The app's main screen: Home (today and the week ahead), all reminders,
/// the calendar and the profile, plus any switched-on optional tabs.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tabIndex = 0;

  static const String _remindersLabel = 'Reminders';
  static const String _proLabel = 'Pro';

  void _openTab(String label) {
    final index = _tabs().indexWhere((t) => t.label == label);
    if (index >= 0 && mounted) setState(() => _tabIndex = index);
  }

  /// Only reachable while the paywall is on (switched-off features have no
  /// tab).
  void _openSubscriptionTab() => _openTab(_proLabel);

  List<_Tab> _tabs() => [
    (
      icon: Icons.home_outlined,
      label: 'Home',
      page: _TodayTab(
        onOpenSubscription: _openSubscriptionTab,
        onSeeAll: () => _openTab(_remindersLabel),
      ),
    ),
    (
      icon: Icons.checklist_rounded,
      label: _remindersLabel,
      page: _AllRemindersTab(onOpenSubscription: _openSubscriptionTab),
    ),
    (
      icon: Icons.calendar_month_outlined,
      label: 'Calendar',
      page: CalendarPage(onOpenSubscription: _openSubscriptionTab),
    ),
    if (Features.analytics)
      (
        icon: Icons.bar_chart_rounded,
        label: 'Analytics',
        page: AnalyticsPage(onOpenSubscription: _openSubscriptionTab),
      ),
    if (Features.paywall)
      (
        icon: Icons.workspace_premium_outlined,
        label: _proLabel,
        page: SubscriptionPage(
          subscription: AppServices.subscription,
          asTab: true,
        ),
      ),
    (
      icon: Icons.person_outline_rounded,
      label: 'Profile',
      page: ProfilePage(asTab: true, onOpenSubscription: _openSubscriptionTab),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Scaffold(
      body: SafeArea(
        top: false,
        child: Stack(
          children: [
            AnimatedSwitcher(
              duration: reduceMotion ? Duration.zero : AppMotion.page,
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
                child: tabs[_tabIndex].page,
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 10,
              child: _GlassBottomNav(
                items: [for (final t in tabs) (icon: t.icon, label: t.label)],
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

// ------------------------------------------------------------ shared actions

Future<void> _createReminder(
  BuildContext context,
  VoidCallback onOpenSubscription,
) async {
  final service = AppServices.reminders;
  if (!service.isPremiumMode) {
    final today = dayOnly(DateTime.now());
    final activeToday = service.currentReminders
        .where((r) => r.isActive && dayOnly(r.dueAt) == today)
        .length;
    if (activeToday >= 5) {
      onOpenSubscription();
      return;
    }
  }

  final result = await showReminderEditor(
    context,
    titleText: 'New reminder',
    onSave: (draft) async {
      await service.createReminder(
        title: draft.title,
        description: draft.description,
        dueAt: draft.dueAt,
        recurrence: draft.recurrence,
        alertMode: draft.alertMode,
        priority: draft.priority,
        alarmSoundId: draft.alarmSoundId,
        notificationSoundId: draft.notificationSoundId,
        remindBeforeMinutes: draft.remindBeforeMinutes,
      );
    },
  );

  if (result == 'premium_required') {
    onOpenSubscription();
    return;
  }
  if (result == 'created' && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Reminder added')));
    await AlarmPermissionPrompt.maybeAsk(context);
  }
}

Future<bool> _confirmDelete(BuildContext context) async {
  return (await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
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

Widget _tile(
  BuildContext context,
  ReminderModel reminder,
  VoidCallback onOpenSubscription,
) {
  return Padding(
    key: ValueKey(reminder.id),
    padding: const EdgeInsets.only(bottom: 10),
    child: ReminderTile(
      reminder: reminder,
      onOpenSubscription: onOpenSubscription,
      onDelete: () async {
        if (!await _confirmDelete(context)) return;
        await AppServices.reminders.deleteReminder(reminder.id);
      },
    ),
  );
}

int _byDueAt(ReminderModel a, ReminderModel b) => a.dueAt.compareTo(b.dueAt);

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 20,
      bottom: 96,
      child: Tooltip(
        message: 'Add reminder',
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            minimumSize: const Size(56, 56),
            padding: EdgeInsets.zero,
          ),
          child: const Icon(
            Icons.add_rounded,
            size: 28,
            semanticLabel: 'Add reminder',
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Home tab

/// Today's reminders and what's coming in the next week.
class _TodayTab extends StatelessWidget {
  const _TodayTab({required this.onOpenSubscription, required this.onSeeAll});

  final VoidCallback onOpenSubscription;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
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
        final today = dayOnly(now);
        final tomorrow = addDays(today, 1);
        final weekEnd = addDays(today, 8);

        final todays =
            reminders.where((r) => dayOnly(r.dueAt) == today).toList()
              ..sort(_byDueAt);
        final remaining = todays.where((r) => r.isActive).length;
        final upcoming =
            reminders
                .where(
                  (r) =>
                      r.isActive &&
                      !r.dueAt.isBefore(tomorrow) &&
                      r.dueAt.isBefore(weekEnd),
                )
                .toList()
              ..sort(_byDueAt);

        return Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 56, 16, 120),
              children: [
                _Header(now: now, reminders: reminders),
                const SizedBox(height: 18),
                Semantics(
                  header: true,
                  child: Text(
                    'Today',
                    style: textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  todays.isEmpty
                      ? 'Nothing due today'
                      : remaining == 0
                      ? 'All done for today'
                      : '$remaining remaining',
                  style: textTheme.bodyMedium?.copyWith(color: tone.mutedText),
                ),
                const SizedBox(height: 12),
                for (final r in todays) _tile(context, r, onOpenSubscription),
                if (reminders.isEmpty)
                  const AppEmptyState(
                    icon: Icons.notifications_none_rounded,
                    title: 'No reminders yet',
                    message: 'Tap + to add your first reminder.',
                  ),
                if (upcoming.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          header: true,
                          child: Text(
                            'Upcoming',
                            style: textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: onSeeAll,
                        child: const Text('See all'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  for (final r in upcoming.take(5))
                    _tile(context, r, onOpenSubscription),
                ],
              ],
            ),
            _AddButton(
              onPressed: () => _createReminder(context, onOpenSubscription),
            ),
          ],
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.now, required this.reminders});

  final DateTime now;
  final List<ReminderModel> reminders;

  String get _greeting {
    if (now.hour < 12) return 'Good morning';
    if (now.hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  Future<void> _openTestAlarm(BuildContext context) async {
    final target = reminders
        .where(
          (r) =>
              r.isActive &&
              (r.alertMode == ReminderAlertMode.ringOnly ||
                  r.alertMode == ReminderAlertMode.ringAndNotify),
        )
        .firstOrNull;
    if (target == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Create a ring reminder first.')),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AlarmScreen(reminderId: target.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final tone = AppTone.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                DateFormat('EEEE, MMM d').format(now),
                style: textTheme.labelMedium?.copyWith(color: tone.mutedText),
              ),
              const SizedBox(height: 2),
              Text(
                _greeting,
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        const _BackupChip(),
        if (kDebugMode && Features.devTools)
          IconButton(
            onPressed: () => _openTestAlarm(context),
            tooltip: 'Test alarm',
            icon: const Icon(Icons.alarm_rounded),
          ),
      ],
    );
  }
}

// ------------------------------------------------------- All reminders tab

enum _ReminderFilter { all, active, completed }

/// Every reminder: what's coming, grouped by day, then what's done.
class _AllRemindersTab extends StatefulWidget {
  const _AllRemindersTab({required this.onOpenSubscription});

  final VoidCallback onOpenSubscription;

  @override
  State<_AllRemindersTab> createState() => _AllRemindersTabState();
}

class _AllRemindersTabState extends State<_AllRemindersTab> {
  _ReminderFilter _filter = _ReminderFilter.all;
  bool _searchOpen = false;
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(ReminderModel r, String query) {
    if (query.isEmpty) return true;
    return r.title.toLowerCase().contains(query) ||
        (r.description ?? '').toLowerCase().contains(query);
  }

  String _dayLabel(DateTime day, DateTime today) {
    if (day == today) return 'Today';
    if (day == addDays(today, 1)) return 'Tomorrow';
    if (day == addDays(today, -1)) return 'Yesterday';
    return DateFormat('EEE, MMM d').format(day);
  }

  Widget _sectionHeader(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: AppTone.of(context).mutedText,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return StreamBuilder<List<ReminderModel>>(
      stream: AppServices.reminders.watchReminders(),
      initialData: AppServices.reminders.currentReminders,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const AppLoadingIndicator(label: 'Loading reminders...');
        }
        final query = _search.text.trim().toLowerCase();
        final today = dayOnly(DateTime.now());
        final matching = snap.data!.where((r) => _matches(r, query));
        final active = matching.where((r) => r.isActive).toList()
          ..sort(_byDueAt);
        final done = matching.where((r) => !r.isActive).toList()
          ..sort((a, b) => b.dueAt.compareTo(a.dueAt));
        final showActive = _filter != _ReminderFilter.completed;
        final showDone = _filter != _ReminderFilter.active;

        final children = <Widget>[];
        if (showActive) {
          DateTime? day;
          for (final r in active) {
            final d = dayOnly(r.dueAt);
            if (d != day) {
              day = d;
              children.add(_sectionHeader(context, _dayLabel(d, today)));
            }
            children.add(_tile(context, r, widget.onOpenSubscription));
          }
        }
        if (showDone && done.isNotEmpty) {
          children.add(_sectionHeader(context, 'Done'));
          for (final r in done) {
            children.add(_tile(context, r, widget.onOpenSubscription));
          }
        }

        return Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 56, 16, 120),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(
                          'Reminders',
                          style: textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => setState(() {
                        _searchOpen = !_searchOpen;
                        if (!_searchOpen) _search.clear();
                      }),
                      tooltip: _searchOpen ? 'Close search' : 'Search',
                      icon: Icon(
                        _searchOpen ? Icons.close : Icons.search_rounded,
                      ),
                    ),
                  ],
                ),
                if (_searchOpen)
                  Padding(
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
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    for (final (filter, label) in const [
                      (_ReminderFilter.all, 'All'),
                      (_ReminderFilter.active, 'Active'),
                      (_ReminderFilter.completed, 'Done'),
                    ]) ...[
                      if (filter != _ReminderFilter.all)
                        const SizedBox(width: 6),
                      Expanded(
                        child: _FilterChip(
                          label: label,
                          selected: _filter == filter,
                          onTap: () => setState(() => _filter = filter),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                if (children.isEmpty)
                  AppEmptyState(
                    icon: Icons.tune_rounded,
                    title: query.isNotEmpty
                        ? 'No matching reminders'
                        : 'Nothing here yet',
                    message: query.isNotEmpty
                        ? 'Try a different word.'
                        : 'Tap + to add a reminder.',
                  )
                else
                  ...children,
              ],
            ),
            _AddButton(
              onPressed: () =>
                  _createReminder(context, widget.onOpenSubscription),
            ),
          ],
        );
      },
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
    return Semantics(
      button: true,
      selected: selected,
      child: AppSurfaceCard(
        dense: true,
        color: selected ? cs.surface : cs.secondary.withValues(alpha: 0.58),
        onTap: onTap,
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              color: selected ? cs.onSurface : tone.mutedText,
            ),
          ),
        ),
      ),
    );
  }
}

/// Whether the reminders are backed up (signed in) or only on this phone.
class _BackupChip extends StatelessWidget {
  const _BackupChip();

  @override
  Widget build(BuildContext context) {
    final tone = AppTone.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: AppServices.reminders.backupOn,
      builder: (context, on, _) {
        final color = on ? tone.success : tone.mutedText;
        return AppSurfaceCard(
          dense: true,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                on ? Icons.cloud_done_rounded : Icons.smartphone_rounded,
                size: 14,
                color: color,
              ),
              const SizedBox(width: 4),
              Text(
                on ? 'Backed up' : 'On this phone',
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: color),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ------------------------------------------------------------- bottom nav

class _GlassBottomNav extends StatelessWidget {
  final List<({IconData icon, String label})> items;
  final int currentIndex;
  final ValueChanged<int> onChanged;

  const _GlassBottomNav({
    required this.items,
    required this.currentIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tone = AppTone.of(context);

    return AnimatedContainer(
      duration: AppMotion.card,
      curve: AppMotion.standard,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
    final color = selected ? cs.primary : tone.mutedText;

    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 22, color: color),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: color,
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
      ),
    );
  }
}
