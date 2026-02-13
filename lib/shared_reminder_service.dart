import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'app_services.dart';
import 'reminder_service.dart';

class SharedReminder {
  final String id;
  final String ownerUid;
  final List<String> participantUids;
  final String reminderId;
  final String reminderTitle;
  final String inviteCode;
  final String inviteLink;
  final DateTime createdAt;

  const SharedReminder({
    required this.id,
    required this.ownerUid,
    required this.participantUids,
    required this.reminderId,
    required this.reminderTitle,
    required this.inviteCode,
    required this.inviteLink,
    required this.createdAt,
  });

  factory SharedReminder.fromDoc(String id, Map<String, dynamic> data) {
    final createdAt = data['createdAt'];
    return SharedReminder(
      id: id,
      ownerUid: (data['ownerUid'] ?? '').toString(),
      participantUids:
          (data['participantUids'] as List<dynamic>? ?? const <dynamic>[])
              .map((e) => e.toString())
              .toList(growable: false),
      reminderId: (data['reminderId'] ?? '').toString(),
      reminderTitle: (data['reminderTitle'] ?? '').toString(),
      inviteCode: (data['inviteCode'] ?? '').toString(),
      inviteLink: (data['inviteLink'] ?? '').toString(),
      createdAt: createdAt is Timestamp ? createdAt.toDate() : DateTime.now(),
    );
  }
}

class SharedReminderService {
  SharedReminderService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> get _ref =>
      _firestore.collection('sharedReminders');

  static Stream<List<SharedReminder>> watchMine(String uid) {
    return _ref.where('participantUids', arrayContains: uid).snapshots().map((
      snap,
    ) {
      return snap.docs
          .map((doc) => SharedReminder.fromDoc(doc.id, doc.data()))
          .toList(growable: false)
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    });
  }

  static Future<String> createSharedReminder(String reminderId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Sign in required.');
    }
    if (!AppServices.reminders.isPremiumMode) {
      throw const PremiumRequiredException(
        feature: 'accountability_sharing',
        message: 'Premium required to create shared reminders.',
      );
    }

    final reminder = await AppServices.reminders.getReminder(reminderId);
    if (reminder == null) {
      throw const ReminderValidationException('Reminder not found.');
    }

    final code = _generateInviteCode();
    final doc = _ref.doc();
    final link = _buildInviteLink(doc.id, code);

    await doc.set({
      'ownerUid': user.uid,
      'participantUids': [user.uid],
      'reminderId': reminderId,
      'reminderTitle': reminder.title,
      'inviteCode': code,
      'inviteLink': link,
      'createdAt': FieldValue.serverTimestamp(),
    });

    return link;
  }

  static Future<void> joinByInvite(String inviteInput) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Sign in required.');
    }
    if (!AppServices.reminders.isPremiumMode) {
      throw const PremiumRequiredException(
        feature: 'accountability_sharing',
        message: 'Premium required to join shared reminders.',
      );
    }

    final parsed = _parseInvite(inviteInput);
    if (parsed.code.isEmpty) {
      throw const ReminderValidationException('Invite code is required.');
    }

    Query<Map<String, dynamic>> query = _ref
        .where('inviteCode', isEqualTo: parsed.code)
        .limit(1);
    if (parsed.sharedId != null && parsed.sharedId!.isNotEmpty) {
      query = _ref
          .where(FieldPath.documentId, isEqualTo: parsed.sharedId)
          .where('inviteCode', isEqualTo: parsed.code)
          .limit(1);
    }

    final snap = await query.get();
    if (snap.docs.isEmpty) {
      throw const ReminderValidationException('Invite code not found.');
    }

    await snap.docs.first.reference.update({
      'participantUids': FieldValue.arrayUnion([user.uid]),
    });
  }

  static String _generateInviteCode() {
    final random = Random();
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final out = StringBuffer();
    for (var i = 0; i < 8; i += 1) {
      out.write(chars[random.nextInt(chars.length)]);
    }
    return out.toString();
  }

  static String _buildInviteLink(String sharedId, String code) {
    return 'snooze://share?sid=$sharedId&code=$code';
  }

  static _ParsedInvite _parseInvite(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return const _ParsedInvite(sharedId: null, code: '');
    }

    final upper = trimmed.toUpperCase();
    if (!upper.contains('://')) {
      return _ParsedInvite(sharedId: null, code: upper);
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null) {
      return _ParsedInvite(sharedId: null, code: upper);
    }

    final sid = uri.queryParameters['sid'];
    final code = (uri.queryParameters['code'] ?? '').toUpperCase();
    return _ParsedInvite(sharedId: sid, code: code);
  }
}

class _ParsedInvite {
  final String? sharedId;
  final String code;

  const _ParsedInvite({required this.sharedId, required this.code});
}
