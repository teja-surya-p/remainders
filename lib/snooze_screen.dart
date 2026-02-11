import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

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
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(minutes: 5))),
    );
    if (time == null) return;

    var dt = DateTime(now.year, now.month, now.day, time.hour, time.minute);
    if (dt.isBefore(now)) dt = dt.add(const Duration(days: 1));
    setState(() => _exact = dt);
  }

  Future<void> _apply(Duration d) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final doc = FirebaseFirestore.instance
        .doc('users/$uid/reminders/${widget.reminderId}');
    final newDueAt = DateTime.now().add(d);

    await doc.update({
      'dueAt': Timestamp.fromDate(newDueAt),
      'updatedAt': FieldValue.serverTimestamp(),
      'lastSnoozedAt': FieldValue.serverTimestamp(),
      'lastSnoozedMinutes': d.inMinutes,
    });

    if (mounted) Navigator.pop(context);
  }

  Future<void> _applyExact() async {
    if (_exact == null) return;
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final doc = FirebaseFirestore.instance
        .doc('users/$uid/reminders/${widget.reminderId}');
    await doc.update({
      'dueAt': Timestamp.fromDate(_exact!),
      'updatedAt': FieldValue.serverTimestamp(),
      'lastSnoozedAt': FieldValue.serverTimestamp(),
      'lastSnoozedMinutes': _exact!.difference(DateTime.now()).inMinutes,
    });
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
              icon: const Icon(Icons.schedule),
              label: Text(
                _exact == null ? 'Pick exact time' : 'Exact: $_exact',
              ),
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: _exact == null ? null : _applyExact,
              child: const Text('Snooze to exact time'),
            ),
          ],
        ),
      ),
    );
  }
}
