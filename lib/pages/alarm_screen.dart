import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../alarm_player.dart';
import '../alarm_vibration.dart';
import '../app_services.dart';
import '../reminder_model.dart';

class AlarmScreen extends StatefulWidget {
  final String reminderId;

  const AlarmScreen({super.key, required this.reminderId});

  @override
  State<AlarmScreen> createState() => _AlarmScreenState();
}

class _AlarmScreenState extends State<AlarmScreen> {
  final TextEditingController _customMinutes = TextEditingController();
  DateTime? _exactSnoozeAt;
  bool _processing = false;

  @override
  void initState() {
    super.initState();
    AlarmPlayer.start();
    AlarmVibration.start();
  }

  Future<void> _stop() async {
    if (_processing) return;
    setState(() => _processing = true);
    await AppServices.reminders.completeReminder(widget.reminderId);
    await AlarmPlayer.stop();
    await AlarmVibration.stop();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _pickExactDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 5),
      initialDate: _exactSnoozeAt ?? now,
    );
    if (date == null) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        _exactSnoozeAt ?? now.add(const Duration(minutes: 5)),
      ),
    );
    if (time == null) return;

    final chosen = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (!chosen.isAfter(now)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose a future date and time.')),
      );
      return;
    }
    setState(() => _exactSnoozeAt = chosen);
  }

  Future<void> _snoozeBy(Duration d) async {
    final newDueAt = DateTime.now().add(d);
    await _applySnooze(newDueAt);
  }

  Future<void> _snoozeCustomMinutes() async {
    final m = int.tryParse(_customMinutes.text.trim());
    if (m == null || m <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter valid custom minutes.')),
      );
      return;
    }
    await _snoozeBy(Duration(minutes: m));
  }

  Future<void> _snoozeExact() async {
    final exact = _exactSnoozeAt;
    if (exact == null) return;
    await _applySnooze(exact);
  }

  Future<void> _applySnooze(DateTime dueAt) async {
    if (_processing) return;
    setState(() => _processing = true);
    try {
      await AppServices.reminders.snoozeReminder(widget.reminderId, dueAt);
      await AlarmPlayer.stop();
      await AlarmVibration.stop();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _processing = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to snooze: $e')));
    }
  }

  @override
  void dispose() {
    _customMinutes.dispose();
    AlarmPlayer.stop();
    AlarmVibration.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [cs.errorContainer.withValues(alpha: 0.85), cs.surface],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: StreamBuilder<List<ReminderModel>>(
              stream: AppServices.reminders.watchReminders(),
              builder: (context, snapshot) {
                final reminder = snapshot.data
                    ?.where((r) => r.id == widget.reminderId)
                    .firstOrNull;
                final title = reminder?.title ?? 'Reminder';
                final snoozeCount = reminder?.consecutiveSnoozes ?? 0;
                final exactLabel = _exactSnoozeAt == null
                    ? 'Pick date & time'
                    : DateFormat('EEE, MMM d • h:mm a').format(_exactSnoozeAt!);

                return ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 114,
                            height: 114,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: cs.error.withValues(alpha: 0.14),
                              border: Border.all(
                                color: cs.error.withValues(alpha: 0.38),
                                width: 2,
                              ),
                            ),
                            child: Icon(Icons.alarm, size: 62, color: cs.error),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Alarm Ringing',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            title,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          if (snoozeCount >= 1) ...[
                            const SizedBox(height: 10),
                            Chip(
                              avatar: const Icon(Icons.snooze, size: 16),
                              label: Text(
                                'Snoozed $snoozeCount time${snoozeCount == 1 ? '' : 's'}',
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            alignment: WrapAlignment.center,
                            children: [
                              FilledButton(
                                onPressed: _processing
                                    ? null
                                    : () =>
                                          _snoozeBy(const Duration(minutes: 5)),
                                child: const Text('Snooze 5m'),
                              ),
                              FilledButton(
                                onPressed: _processing
                                    ? null
                                    : () => _snoozeBy(
                                        const Duration(minutes: 10),
                                      ),
                                child: const Text('Snooze 10m'),
                              ),
                              FilledButton(
                                onPressed: _processing
                                    ? null
                                    : () => _snoozeBy(
                                        const Duration(minutes: 30),
                                      ),
                                child: const Text('Snooze 30m'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _customMinutes,
                            enabled: !_processing,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Custom minutes',
                              hintText: 'e.g. 15',
                            ),
                          ),
                          const SizedBox(height: 10),
                          FilledButton.tonal(
                            onPressed: _processing
                                ? null
                                : _snoozeCustomMinutes,
                            child: const Text('Snooze by custom minutes'),
                          ),
                          const SizedBox(height: 14),
                          FilledButton.tonalIcon(
                            onPressed: _processing ? null : _pickExactDateTime,
                            icon: const Icon(Icons.event),
                            label: Text(exactLabel),
                          ),
                          const SizedBox(height: 10),
                          FilledButton(
                            onPressed: _processing || _exactSnoozeAt == null
                                ? null
                                : _snoozeExact,
                            child: const Text('Snooze to date & time'),
                          ),
                          const SizedBox(height: 18),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: cs.error,
                              foregroundColor: cs.onError,
                            ),
                            onPressed: _processing ? null : _stop,
                            icon: const Icon(Icons.stop),
                            label: const Text('Stop Alarm'),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

extension _IterableFirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    if (isEmpty) return null;
    return first;
  }
}
