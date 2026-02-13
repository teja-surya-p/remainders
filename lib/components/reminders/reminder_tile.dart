import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_services.dart';
import '../../reminder_model.dart';
import '../../reminder_service.dart';
import '../../theme/app_tokens.dart';
import '../common/app_ui.dart';
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
    final tone = AppTone.of(context);
    final checked = reminder.completed || reminder.missed;
    final repeatLabel = _repeatLabel(reminder.recurrence);

    return AppSurfaceCard(
      onTap: () => _edit(context),
      onLongPress: onDelete,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CompletionKnob(
            checked: checked,
            onTap: reminder.missed
                ? null
                : () async {
                    if (checked) return;
                    await AppServices.reminders.completeReminder(reminder.id);
                  },
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        reminder.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          decoration: checked
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => _edit(context),
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        Icons.more_horiz_rounded,
                        color: tone.mutedText,
                      ),
                    ),
                  ],
                ),
                if ((reminder.description ?? '').trim().isNotEmpty)
                  Text(
                    reminder.description!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: tone.mutedText),
                  ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _MetaChip(
                      icon: Icons.schedule_rounded,
                      label: DateFormat('h:mm a').format(reminder.dueAt),
                    ),
                    ..._alertModeIcons(context),
                    _MetaChip(
                      icon: Icons.flag_rounded,
                      label: _priorityLabel(reminder.priority),
                      color: _priorityColor(
                        context,
                        reminder.priority,
                      ).withValues(alpha: 0.13),
                      foreground: _priorityColor(context, reminder.priority),
                    ),
                    if (repeatLabel != null)
                      _MetaChip(icon: Icons.repeat_rounded, label: repeatLabel),
                    if (reminder.consecutiveSnoozes >= 1)
                      _MetaChip(
                        icon: Icons.snooze_rounded,
                        label: 'Snoozed ${reminder.consecutiveSnoozes}x',
                        color: tone.warning.withValues(alpha: 0.16),
                        foreground: tone.warning,
                      ),
                    if (reminder.missed)
                      _MetaChip(
                        icon: Icons.warning_amber_rounded,
                        label: 'Missed',
                        color: cs.error.withValues(alpha: 0.12),
                        foreground: cs.error,
                      ),
                  ],
                ),
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
            icon: const Icon(Icons.delete_outline_rounded),
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
            ? 'Daily (${recurrence.timesOfDay.length}x)'
            : 'Daily';
      case RepeatType.weekly:
        return 'Weekly';
      case RepeatType.interval:
        final every = recurrence.intervalDays ?? 1;
        return 'Every $every day${every == 1 ? '' : 's'}';
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
            color: AppTone.of(context).chart3.withValues(alpha: 0.15),
            foreground: AppTone.of(context).chart3,
          ),
        ];
      case ReminderAlertMode.ringOnly:
        return [
          _MetaChip(
            icon: Icons.alarm_rounded,
            label: 'Ring',
            color: iconColor.withValues(alpha: 0.15),
            foreground: iconColor,
          ),
        ];
      case ReminderAlertMode.ringAndNotify:
        return [
          _MetaChip(
            icon: Icons.notifications_active_outlined,
            label: 'Notify',
            color: AppTone.of(context).chart3.withValues(alpha: 0.15),
            foreground: AppTone.of(context).chart3,
          ),
          _MetaChip(
            icon: Icons.alarm_rounded,
            label: 'Ring',
            color: iconColor.withValues(alpha: 0.15),
            foreground: iconColor,
          ),
        ];
    }
  }

  Color _priorityColor(BuildContext context, ReminderPriority priority) {
    switch (priority) {
      case ReminderPriority.low:
        return AppTone.of(context).chart2;
      case ReminderPriority.medium:
        return AppTone.of(context).warning;
      case ReminderPriority.high:
        return Theme.of(context).colorScheme.error;
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

class _CompletionKnob extends StatelessWidget {
  final bool checked;
  final VoidCallback? onTap;

  const _CompletionKnob({required this.checked, this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(99),
      child: Container(
        margin: const EdgeInsets.only(top: 2),
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: checked ? cs.primary : Colors.transparent,
          border: Border.all(
            color: checked
                ? cs.primary
                : AppTone.of(context).mutedText.withValues(alpha: 0.4),
            width: 2,
          ),
        ),
        alignment: Alignment.center,
        child: checked
            ? Icon(Icons.check_rounded, size: 14, color: cs.onPrimary)
            : const SizedBox.shrink(),
      ),
    );
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
      color: cs.primary.withValues(alpha: 0.10),
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
    final bg = color ?? cs.secondary.withValues(alpha: 0.7);
    final fg = foreground ?? AppTone.of(context).mutedText;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
