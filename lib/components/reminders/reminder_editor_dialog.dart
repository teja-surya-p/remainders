import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../common/app_ui.dart';
import '../../reminder_model.dart';
import '../../reminder_service.dart';

class ReminderDraft {
  final String title;
  final String? description;
  final DateTime dueAt;
  final ReminderRecurrence recurrence;
  final ReminderAlertMode alertMode;
  final ReminderPriority priority;

  ReminderDraft({
    required this.title,
    required this.dueAt,
    this.description,
    ReminderRecurrence? recurrence,
    this.alertMode = ReminderAlertMode.ringAndNotify,
    this.priority = ReminderPriority.medium,
  }) : recurrence = recurrence ?? ReminderRecurrence();
}

class ReminderEditorDialog extends StatefulWidget {
  final String titleText;
  final bool premiumEnabled;
  final ReminderDraft? initial;
  final Future<void> Function(ReminderDraft draft) onSave;

  const ReminderEditorDialog({
    super.key,
    required this.titleText,
    required this.premiumEnabled,
    required this.onSave,
    this.initial,
  });

  @override
  State<ReminderEditorDialog> createState() => _ReminderEditorDialogState();
}

class _ReminderEditorDialogState extends State<ReminderEditorDialog> {
  late final TextEditingController _title;
  late final TextEditingController _desc;
  late final TextEditingController _intervalDays;

  DateTime? _dueAt;
  DateTime? _endAt;

  late RepeatType _repeatType;
  late ReminderAlertMode _alertMode;
  late ReminderPriority _priority;
  late final Set<int> _weekdays;
  late final List<int> _times;

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _title = TextEditingController(text: initial?.title ?? '');
    _desc = TextEditingController(text: initial?.description ?? '');
    _intervalDays = TextEditingController(
      text: (initial?.recurrence.intervalDays ?? 1).toString(),
    );

    _dueAt = initial?.dueAt;
    _repeatType = initial?.recurrence.type ?? RepeatType.none;
    _alertMode = initial?.alertMode ?? ReminderAlertMode.ringAndNotify;
    _priority = initial?.priority ?? ReminderPriority.medium;
    _weekdays = {...(initial?.recurrence.weekdays ?? const <int>[])};
    _times = [...(initial?.recurrence.timesOfDay ?? const <int>[])]..sort();
    if (_times.isEmpty && _dueAt != null) {
      _times.add(minutesOfDay(_dueAt!));
    }
    _endAt = initial?.recurrence.endAt;
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _intervalDays.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 5),
      initialDate: _dueAt ?? now,
    );
    if (date == null) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dueAt ?? now),
    );
    if (time == null) return;

    setState(() {
      _dueAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      if (_times.isEmpty) {
        _times.add(minutesOfDay(_dueAt!));
      } else {
        _times[0] = minutesOfDay(_dueAt!);
      }
      if (_repeatType == RepeatType.weekly && _weekdays.isEmpty) {
        _weekdays.add(_dueAt!.weekday);
      }
    });
  }

  Future<void> _addTime() async {
    final base = _dueAt ?? DateTime.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (picked == null) return;

    final minute = picked.hour * 60 + picked.minute;
    setState(() {
      if (!widget.premiumEnabled) {
        _times
          ..clear()
          ..add(minute);
      } else {
        if (!_times.contains(minute)) {
          _times.add(minute);
          _times.sort();
        }
      }
    });
  }

  DateTime? _resolveDueAtForSave() {
    if (_dueAt != null) return _dueAt;
    if (_repeatType == RepeatType.none) return null;
    if (_times.isEmpty) return null;

    final now = DateTime.now();
    var candidate = dateWithMinutes(now, _times.first);
    if (candidate.isBefore(now)) {
      candidate = candidate.add(const Duration(days: 1));
    }
    return candidate;
  }

  Future<void> _pickEndDate() async {
    final now = DateTime.now();
    final start = _dueAt ?? now;
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(start.year, start.month, start.day),
      lastDate: DateTime(now.year + 5),
      initialDate: _endAt ?? start,
    );
    if (date == null) return;

    setState(() {
      _endAt = DateTime(date.year, date.month, date.day, 23, 59);
    });
  }

  void _setRepeatType(RepeatType type) {
    setState(() {
      _repeatType = type;
      if (type == RepeatType.none) {
        _weekdays.clear();
        _endAt = null;
      }
      if (type == RepeatType.weekly && _weekdays.isEmpty) {
        final base = _dueAt ?? DateTime.now();
        _weekdays.add(base.weekday);
      }
      if (!widget.premiumEnabled) {
        _endAt = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final dueText = _dueAt == null
        ? 'Pick date & time'
        : DateFormat('EEE, MMM d • h:mm a').format(_dueAt!);

    final typeOptions = <RepeatType>[
      RepeatType.none,
      RepeatType.daily,
      RepeatType.weekly,
      if (widget.premiumEnabled) RepeatType.interval,
    ];

    final hasValidDateInput =
        _dueAt != null || (_repeatType != RepeatType.none && _times.isNotEmpty);
    final canSave = _title.text.trim().isNotEmpty && hasValidDateInput;

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      title: AppSectionHeader(
        title: widget.titleText,
        subtitle: 'Set schedule, alert mode, and recurrence',
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'Name'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _desc,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 14),
              AppSurfaceCard(
                dense: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AppSectionHeader(
                      title: 'Date & Time',
                      subtitle: 'Required for one-time reminders',
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _pickDateTime,
                      icon: const Icon(Icons.schedule),
                      label: Text(dueText),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<ReminderAlertMode>(
                      initialValue: _alertMode,
                      decoration: const InputDecoration(
                        labelText: 'Alert type',
                      ),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _alertMode = value);
                      },
                      items: const [
                        DropdownMenuItem(
                          value: ReminderAlertMode.notifyOnly,
                          child: Text('Only notify'),
                        ),
                        DropdownMenuItem(
                          value: ReminderAlertMode.ringOnly,
                          child: Text('Only ring'),
                        ),
                        DropdownMenuItem(
                          value: ReminderAlertMode.ringAndNotify,
                          child: Text('Ring and notify'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<ReminderPriority>(
                      initialValue: _priority,
                      decoration: const InputDecoration(
                        labelText: 'Alarm priority',
                      ),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _priority = value);
                      },
                      items: const [
                        DropdownMenuItem(
                          value: ReminderPriority.low,
                          child: Text('Low'),
                        ),
                        DropdownMenuItem(
                          value: ReminderPriority.medium,
                          child: Text('Medium'),
                        ),
                        DropdownMenuItem(
                          value: ReminderPriority.high,
                          child: Text('High'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              AppSurfaceCard(
                dense: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AppSectionHeader(
                      title: 'Repeat',
                      subtitle: 'Configure recurring schedule',
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<RepeatType>(
                      initialValue: _repeatType,
                      decoration: const InputDecoration(
                        labelText: 'Recurrence type',
                      ),
                      onChanged: (value) {
                        if (value != null) _setRepeatType(value);
                      },
                      items: [
                        for (final type in typeOptions)
                          DropdownMenuItem(
                            value: type,
                            child: Text(_typeLabel(type)),
                          ),
                      ],
                    ),
                    if (_repeatType == RepeatType.weekly) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: List.generate(7, (i) {
                          final day = i + 1;
                          const labels = [
                            'Mon',
                            'Tue',
                            'Wed',
                            'Thu',
                            'Fri',
                            'Sat',
                            'Sun',
                          ];
                          final selected = _weekdays.contains(day);
                          final allowed =
                              widget.premiumEnabled ||
                              selected ||
                              _weekdays.isEmpty;
                          return FilterChip(
                            label: Text(labels[i]),
                            selected: selected,
                            onSelected: allowed
                                ? (_) {
                                    setState(() {
                                      if (selected) {
                                        _weekdays.remove(day);
                                      } else {
                                        if (!widget.premiumEnabled) {
                                          _weekdays
                                            ..clear()
                                            ..add(day);
                                        } else {
                                          _weekdays.add(day);
                                        }
                                      }
                                    });
                                  }
                                : null,
                          );
                        }),
                      ),
                    ],
                    if (_repeatType == RepeatType.interval) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: _intervalDays,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Repeat every N days',
                        ),
                      ),
                    ],
                    if (_repeatType != RepeatType.none) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Text(
                            'Times per day',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: _addTime,
                            icon: const Icon(Icons.add_alarm),
                            label: const Text('Add time'),
                          ),
                        ],
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: _times.map((m) {
                          final label = _formatMinute(m);
                          return InputChip(
                            label: Text(label),
                            onDeleted: _times.length <= 1
                                ? null
                                : () {
                                    setState(() {
                                      _times.remove(m);
                                    });
                                  },
                          );
                        }).toList(),
                      ),
                    ],
                    if (_repeatType != RepeatType.none &&
                        widget.premiumEnabled) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Text('Date range end'),
                          const Spacer(),
                          TextButton(
                            onPressed: _pickEndDate,
                            child: Text(
                              _endAt == null
                                  ? 'Set end date'
                                  : DateFormat('MMM d, y').format(_endAt!),
                            ),
                          ),
                          if (_endAt != null)
                            IconButton(
                              onPressed: () => setState(() => _endAt = null),
                              icon: const Icon(Icons.clear),
                            ),
                        ],
                      ),
                    ],
                    if (_repeatType != RepeatType.none &&
                        !widget.premiumEnabled) ...[
                      const SizedBox(height: 8),
                      AppInlineMessage(
                        text:
                            'Free plan supports basic daily/weekly recurrence only.',
                        icon: Icons.workspace_premium,
                      ),
                    ],
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, 'cancel'),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: !canSave || _saving
              ? null
              : () async {
                  final dueAt = _resolveDueAtForSave();
                  if (dueAt == null) {
                    setState(() {
                      _error =
                          'Choose date & time, or set repeat with at least one time.';
                    });
                    return;
                  }

                  final intervalDays = int.tryParse(_intervalDays.text.trim());
                  final recurrence = ReminderRecurrence(
                    type: _repeatType,
                    weekdays: _weekdays.toList(),
                    intervalDays: _repeatType == RepeatType.interval
                        ? intervalDays
                        : null,
                    timesOfDay: _times,
                    endAt: widget.premiumEnabled ? _endAt : null,
                  );

                  final draft = ReminderDraft(
                    title: _title.text.trim(),
                    description: _desc.text.trim().isEmpty
                        ? null
                        : _desc.text.trim(),
                    dueAt: dueAt,
                    recurrence: recurrence,
                    alertMode: _alertMode,
                    priority: _priority,
                  );

                  setState(() {
                    _saving = true;
                    _error = null;
                  });

                  try {
                    await widget.onSave(draft);
                    if (context.mounted) Navigator.pop(context, 'created');
                  } catch (e) {
                    if (e is PremiumRequiredException) {
                      if (context.mounted) {
                        Navigator.pop(context, 'premium_required');
                      }
                      return;
                    }
                    if (!mounted) return;
                    setState(() {
                      _error = e.toString();
                    });
                  } finally {
                    if (!mounted) return;
                    setState(() {
                      _saving = false;
                    });
                  }
                },
          child: const Text('Save'),
        ),
      ],
    );
  }

  String _typeLabel(RepeatType type) {
    switch (type) {
      case RepeatType.none:
        return 'None';
      case RepeatType.daily:
        return 'Daily';
      case RepeatType.weekly:
        return 'Weekly';
      case RepeatType.interval:
        return 'Every N days';
    }
  }

  String _formatMinute(int minute) {
    final h = (minute ~/ 60) % 24;
    final m = minute % 60;
    final suffix = h >= 12 ? 'PM' : 'AM';
    final hour12 = h % 12 == 0 ? 12 : h % 12;
    final mm = m.toString().padLeft(2, '0');
    return '$hour12:$mm $suffix';
  }
}
