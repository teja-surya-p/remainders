import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'notifs.dart';
import 'repeat_utils.dart';

class ReminderScheduler {
  ReminderScheduler._();

  static const Duration _leadTime = Duration(minutes: 30);
  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;

  static Future<void> start() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final col = FirebaseFirestore.instance.collection('users/$uid/reminders');

    await _sub?.cancel();
    _sub = col.snapshots().listen((snap) async {
      for (final change in snap.docChanges) {
        final doc = change.doc;
        final data = doc.data();
        if (data == null) continue;

        final completed = (data['completed'] ?? false) as bool;
        final mainId = (data['notifIdMain'] as num?)?.toInt();
        final preId = (data['notifIdPre'] as num?)?.toInt();
        final repeatType =
            repeatTypeFromString(data['repeatType'] as String?);
        final repeatDays = parseRepeatDays(data['repeatDays']);
        final repeatTime = (data['repeatTime'] as num?)?.toInt();
        final isRepeating =
            repeatType != RepeatType.none && repeatDays.isNotEmpty;

        if (change.type == DocumentChangeType.removed || completed) {
          if (mainId != null) await Notifs.cancel(mainId);
          if (preId != null) await Notifs.cancel(preId);
          continue;
        }

        final dueTs = data['dueAt'];
        if (dueTs is! Timestamp) continue;

        final dueAt = dueTs.toDate();
        final now = DateTime.now();

        if (dueAt.isBefore(now.subtract(const Duration(seconds: 5)))) {
          if (isRepeating) {
            final minutes = repeatTime ?? minutesOfDay(dueAt);
            final next = nextOccurrence(
              from: now.add(const Duration(seconds: 1)),
              type: repeatType,
              days: repeatDays,
              minutes: minutes,
            );
            if (next != null) {
              await doc.reference.update({
                'dueAt': Timestamp.fromDate(next),
                'lastOccurrenceAt': Timestamp.fromDate(dueAt),
                'lastOccurrenceStatus': 'missed',
                'updatedAt': FieldValue.serverTimestamp(),
                if (repeatTime == null) 'repeatTime': minutes,
              });
            }
          } else {
            await doc.reference.update({
              'completed': true,
              'missed': true,
              'missedAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }

          if (mainId != null) await Notifs.cancel(mainId);
          if (preId != null) await Notifs.cancel(preId);
          continue;
        }
        final preTime = dueAt.subtract(_leadTime);
        final shouldPre = preTime.isAfter(now);

        final nextMainId = mainId ?? _nextId();
        final nextPreId = nextMainId + 1;

        final updates = <String, dynamic>{};
        if (mainId == null) updates['notifIdMain'] = nextMainId;
        if (shouldPre && preId == null) updates['notifIdPre'] = nextPreId;
        if (!shouldPre && preId != null) updates['notifIdPre'] = FieldValue.delete();
        if (isRepeating && repeatTime == null) {
          updates['repeatTime'] = minutesOfDay(dueAt);
        }
        if (updates.isNotEmpty) {
          await doc.reference.update(updates);
        }

        if (mainId != null) await Notifs.cancel(mainId);
        if (preId != null) await Notifs.cancel(preId);

        if (dueAt.isBefore(now.add(const Duration(seconds: 5)))) {
          continue;
        }

        final title = (data['title'] ?? 'Reminder') as String;
        final desc = (data['description'] ?? '') as String;

        await Notifs.schedule(
          id: nextMainId,
          title: title,
          body: desc.isEmpty ? null : desc,
          whenLocal: dueAt,
          payload: 'alarm:${doc.id}',
          isAlarm: true,
        );

        if (shouldPre) {
          await Notifs.schedule(
            id: nextPreId,
            title: 'Upcoming reminder',
            body: '$title in ${_leadTime.inMinutes} minutes',
            whenLocal: preTime,
            payload: 'pre:${doc.id}',
          );
        }
      }
    });
  }

  static Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }

  static int _nextId() => DateTime.now().millisecondsSinceEpoch % 2147483647;
}
