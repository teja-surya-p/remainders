import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_services.dart';

class SnoozeScreen extends StatefulWidget {
  final String reminderId;
  const SnoozeScreen({super.key, required this.reminderId});

  @override
  State<SnoozeScreen> createState() => _SnoozeScreenState();
}

class _SnoozeScreenState extends State<SnoozeScreen> {
  final _minutes = TextEditingController();
  DateTime? _exact;

  @override
  void dispose() {
    _minutes.dispose();
    super.dispose();
  }

  Future<void> _pickExact() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 5),
      initialDate: _exact ?? now,
    );
    if (date == null) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        _exact ?? now.add(const Duration(minutes: 5)),
      ),
    );
    if (time == null) return;

    final dt = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (!dt.isAfter(now)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose a future date and time.')),
      );
      return;
    }
    setState(() => _exact = dt);
  }

  Future<void> _apply(Duration d) async {
    final newDueAt = DateTime.now().add(d);
    await AppServices.reminders.snoozeReminder(widget.reminderId, newDueAt);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _applyExact() async {
    if (_exact == null) return;
    await AppServices.reminders.snoozeReminder(widget.reminderId, _exact!);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Snooze')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              children: [
                FilledButton(
                  onPressed: () => _apply(const Duration(minutes: 5)),
                  child: const Text('5 min'),
                ),
                FilledButton(
                  onPressed: () => _apply(const Duration(minutes: 10)),
                  child: const Text('10 min'),
                ),
                FilledButton(
                  onPressed: () => _apply(const Duration(minutes: 30)),
                  child: const Text('30 min'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _minutes,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Custom minutes',
                hintText: 'e.g. 15',
              ),
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: () {
                final m = int.tryParse(_minutes.text.trim());
                if (m == null || m <= 0) return;
                _apply(Duration(minutes: m));
              },
              child: const Text('Snooze by minutes'),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _pickExact,
              icon: const Icon(Icons.event),
              label: Text(
                _exact == null
                    ? 'Pick date & time'
                    : DateFormat('EEE, MMM d • h:mm a').format(_exact!),
              ),
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: _exact == null ? null : _applyExact,
              child: const Text('Snooze to date & time'),
            ),
          ],
        ),
      ),
    );
  }
}
