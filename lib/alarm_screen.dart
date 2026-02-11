import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'alarm_vibration.dart';
import 'alarm_player.dart';
import 'notifs.dart';
import 'repeat_utils.dart';

class AlarmScreen extends StatefulWidget {
  final String reminderId;
  const AlarmScreen({super.key, required this.reminderId});

  @override
  State<AlarmScreen> createState() => _AlarmScreenState();
}

class _AlarmScreenState extends State<AlarmScreen> {
  @override
  void initState() {
    super.initState();
    AlarmPlayer.start();
    AlarmVibration.start();
  }

  Future<void> _stop() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final doc = FirebaseFirestore.instance
        .doc('users/$uid/reminders/${widget.reminderId}');

    Map<String, dynamic>? data;
    try {
      final snap = await doc.get();
      data = snap.data();
      final mainId = (data?['notifIdMain'] as num?)?.toInt();
      final preId = (data?['notifIdPre'] as num?)?.toInt();
      if (mainId != null) await Notifs.cancel(mainId);
      if (preId != null) await Notifs.cancel(preId);
    } catch (_) {}

    final repeatType = repeatTypeFromString(data?['repeatType'] as String?);
    final repeatDays = parseRepeatDays(data?['repeatDays']);
    final repeatTime = (data?['repeatTime'] as num?)?.toInt();
    final isRepeating =
        repeatType != RepeatType.none && repeatDays.isNotEmpty;
    final dueAt = (data?['dueAt'] as Timestamp?)?.toDate() ?? DateTime.now();

    if (isRepeating) {
      final minutes = repeatTime ?? minutesOfDay(dueAt);
      final next = nextOccurrence(
        from: DateTime.now().add(const Duration(seconds: 1)),
        type: repeatType,
        days: repeatDays,
        minutes: minutes,
      );
      if (next != null) {
        await doc.update({
          'dueAt': Timestamp.fromDate(next),
          'completed': false,
          'missed': false,
          'lastOccurrenceAt': Timestamp.fromDate(dueAt),
          'lastOccurrenceStatus': 'stopped',
          'updatedAt': FieldValue.serverTimestamp(),
          if (repeatTime == null) 'repeatTime': minutes,
        });
      }
    } else {
      await doc.update({
        'completed': true,
        'missed': false,
        'lastOccurrenceAt': Timestamp.fromDate(dueAt),
        'lastOccurrenceStatus': 'stopped',
        'updatedAt': FieldValue.serverTimestamp(),
        'dismissedAt': FieldValue.serverTimestamp(),
      });
    }

    await AlarmPlayer.stop();
    await AlarmVibration.stop();

    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    AlarmPlayer.stop();
    AlarmVibration.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final doc = FirebaseFirestore.instance
        .doc('users/$uid/reminders/${widget.reminderId}');

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: doc.snapshots(),
            builder: (context, snap) {
              final data = snap.data?.data();
              final title = (data?['title'] ?? 'Reminder') as String;
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.alarm, size: 72),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _stop,
                      icon: const Icon(Icons.stop),
                      label: const Text('Stop'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
