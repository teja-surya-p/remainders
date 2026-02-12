import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_services.dart';
import '../common/app_ui.dart';
import '../../reminder_model.dart';
import '../../reminder_service.dart';
import 'reminder_editor_dialog.dart';

class ReminderTile extends StatelessWidget {
  final ReminderModel reminder;
  final VoidCallback onOpenSubscription;
  final Future<void> Function() onDelete;

  const ReminderTile({
    super.key,
    required this.reminder,
    required this.onOpenSubscription,
    required this.onDelete,
  });

  Future<void> _edit(BuildContext context) async {
    try {
      final result = await showDialog<String>(
        context: context,
        builder: (_) => ReminderEditorDialog(
          titleText: 'Edit reminder',
          premiumEnabled: AppServices.reminders.isPremiumMode,
          initial: ReminderDraft(
            title: reminder.title,
            description: reminder.description,
            dueAt: reminder.dueAt,
            recurrence: reminder.recurrence,
            alertMode: reminder.alertMode,
            priority: reminder.priority,
          ),
          onSave: (draft) async {
            final updated = reminder.copyWith(
              title: draft.title,
              description: draft.description,
              dueAt: draft.dueAt,
              recurrence: draft.recurrence,
              alertMode: draft.alertMode,
              priority: draft.priority,
              completed: false,
              missed: false,
            );
            await AppServices.reminders.updateReminder(updated);
          },
        ),
      );
      if (result == 'premium_required') {
        onOpenSubscription();
      }
    } on PremiumRequiredException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
      onOpenSubscription();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final checked = reminder.completed || reminder.missed;
    final repeatLabel = _repeatLabel(reminder.recurrence);
    final priorityColor = _priorityColor(context, reminder.priority);

    return AppSurfaceCard(
      onTap: () => _edit(context),
      onLongPress: () {
        onDelete();
      },
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: checked,
            onChanged: reminder.missed
                ? null
                : (v) async {
                    if (v == true) {
                      await AppServices.reminders.completeReminder(reminder.id);
                    }
                  },
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        reminder.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              decoration: checked
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                      ),
                    ),
                    if (reminder.missed) ...[
                      const SizedBox(width: 8),
                      const _Badge(text: 'Missed'),
                    ],
                    if (reminder.recurrence.isRepeating) ...[
                      const SizedBox(width: 6),
                      const _Badge(text: 'Repeat', outlined: true),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _MetaChip(
                      icon: Icons.schedule,
                      label: DateFormat('h:mm a').format(reminder.dueAt),
                    ),
                    ..._alertModeIcons(context),
                    _MetaChip(
                      icon: Icons.flag,
                      label: _priorityLabel(reminder.priority),
                      color: priorityColor.withValues(alpha: 0.14),
                      foreground: priorityColor,
                    ),
                    if (reminder.consecutiveSnoozes >= 1)
                      _SnoozeCountBadge(count: reminder.consecutiveSnoozes),
                  ],
                ),
                if ((reminder.description ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    reminder.description!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
                if (repeatLabel != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    repeatLabel,
                    style: Theme.of(
                      context,
                    ).textTheme.labelMedium?.copyWith(color: cs.primary),
                  ),
                ],
                if ((reminder.suggestionMessage ?? '').isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _SuggestionCard(
                    reminder: reminder,
                    onOpenSubscription: onOpenSubscription,
                  ),
                ],
                if (reminder.missed && reminder.streakBeforeMiss > 0) ...[
                  const SizedBox(height: 10),
                  FilledButton.tonal(
                    onPressed: () async {
                      try {
                        await AppServices.reminders.recoverStreak(reminder.id);
                      } on PremiumRequiredException {
                        onOpenSubscription();
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text(e.toString())));
                        }
                      }
                    },
                    child: const Text('Recover streak'),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: onDelete,
            tooltip: 'Delete reminder',
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }

  String? _repeatLabel(ReminderRecurrence recurrence) {
    switch (recurrence.type) {
      case RepeatType.none:
        return null;
      case RepeatType.daily:
        return recurrence.timesOfDay.length > 1
            ? 'Repeats daily (${recurrence.timesOfDay.length} times/day)'
            : 'Repeats daily';
      case RepeatType.weekly:
        return 'Repeats weekly';
      case RepeatType.interval:
        final every = recurrence.intervalDays ?? 1;
        return 'Repeats every $every day${every == 1 ? '' : 's'}';
    }
  }

  List<Widget> _alertModeIcons(BuildContext context) {
    final iconColor = Theme.of(context).colorScheme.primary;
    switch (reminder.alertMode) {
      case ReminderAlertMode.notifyOnly:
        return [
          _MetaChip(
            icon: Icons.notifications_active_outlined,
            label: 'Notify',
            foreground: iconColor,
          ),
        ];
      case ReminderAlertMode.ringOnly:
        return [
          _MetaChip(icon: Icons.alarm, label: 'Ring', foreground: iconColor),
        ];
      case ReminderAlertMode.ringAndNotify:
        return [
          _MetaChip(
            icon: Icons.notifications_active_outlined,
            label: 'Notify',
            foreground: iconColor,
          ),
          _MetaChip(icon: Icons.alarm, label: 'Ring', foreground: iconColor),
        ];
    }
  }

  Color _priorityColor(BuildContext context, ReminderPriority priority) {
    final cs = Theme.of(context).colorScheme;
    switch (priority) {
      case ReminderPriority.low:
        return cs.secondary;
      case ReminderPriority.medium:
        return cs.tertiary;
      case ReminderPriority.high:
        return cs.error;
    }
  }

  String _priorityLabel(ReminderPriority priority) {
    switch (priority) {
      case ReminderPriority.low:
        return 'Low';
      case ReminderPriority.medium:
        return 'Medium';
      case ReminderPriority.high:
        return 'High';
    }
  }
}

class _SuggestionCard extends StatelessWidget {
  final ReminderModel reminder;
  final VoidCallback onOpenSubscription;

  const _SuggestionCard({
    required this.reminder,
    required this.onOpenSubscription,
  });

  @override
  Widget build(BuildContext context) {
    final isPremium = AppServices.reminders.isPremiumMode;
    final cs = Theme.of(context).colorScheme;

    return AppSurfaceCard(
      dense: true,
      color: cs.primaryContainer.withValues(alpha: 0.45),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            reminder.suggestionMessage ?? '',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: () async {
              if (!isPremium) {
                onOpenSubscription();
                return;
              }
              await AppServices.reminders.applySuggestion(reminder.id);
            },
            child: Text(isPremium ? 'Auto-adjust' : 'Premium required'),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final bool outlined;

  const _Badge({required this.text, this.outlined = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = outlined ? Colors.transparent : cs.primaryContainer;
    final fg = outlined ? cs.primary : cs.onPrimaryContainer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: outlined ? Border.all(color: cs.primary) : null,
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}

class _SnoozeCountBadge extends StatelessWidget {
  final int count;

  const _SnoozeCountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _MetaChip(
      icon: Icons.snooze,
      label: '$count',
      color: cs.tertiaryContainer,
      foreground: cs.onTertiaryContainer,
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final Color? foreground;

  const _MetaChip({
    required this.icon,
    required this.label,
    this.color,
    this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color ?? cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: foreground ?? cs.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: foreground ?? cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
