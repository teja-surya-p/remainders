import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../app_services.dart';
import '../notifs.dart';
import '../reminder_scheduler.dart';
import 'google_auth.dart';

/// Why an account action couldn't finish, in words for the user.
class AccountException implements Exception {
  const AccountException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Sign-out and account deletion. Reminders live on the phone, so neither
/// removes them unless the user asks.
class AccountService {
  AccountService._();

  static const Duration _serverTimeout = Duration(seconds: 30);

  // Firestore allows 500 writes per batch.
  static const int _batchSize = 400;

  /// Uploads changes not yet backed up, waiting up to [timeout]. False if
  /// some exist only on this phone (e.g. offline).
  static Future<bool> finishBackup({
    Duration timeout = const Duration(seconds: 5),
  }) => AppServices.reminders.flushBackup(timeout: timeout);

  /// Signs out. Backup stops; reminders and alarms stay on this phone
  /// unless [removeFromPhone].
  static Future<void> signOut({required bool removeFromPhone}) async {
    // Stop uploads now rather than when the sign-out event arrives.
    await AppServices.reminders.attachAccount(null);
    await GoogleAuth.signOut();
    await FirebaseAuth.instance.signOut();
    if (removeFromPhone) await removeFromThisPhone();
  }

  /// Confirms the signed-in person is the account owner: Firebase only
  /// deletes an account after a recent sign-in. [askPassword] is shown for
  /// email accounts. Returns false if the user backed out.
  static Future<bool> reauthenticate({
    required Future<String?> Function(String email) askPassword,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final providers = {for (final p in user.providerData) p.providerId};
    final email = user.email;

    AuthCredential? credential;
    if (providers.contains(GoogleAuthProvider.PROVIDER_ID)) {
      try {
        credential = await GoogleAuth.credential();
      } on GoogleAuthException catch (e) {
        throw AccountException(e.message);
      }
    } else if (providers.contains(EmailAuthProvider.PROVIDER_ID) &&
        email != null) {
      final password = await askPassword(email);
      if (password == null) return false;
      credential = EmailAuthProvider.credential(
        email: email,
        password: password,
      );
    } else {
      throw const AccountException(
        "This sign-in method can't be confirmed here. Sign out, sign in "
        'again, then delete the account.',
      );
    }
    if (credential == null) return false;

    try {
      await user.reauthenticateWithCredential(credential);
      return true;
    } on FirebaseAuthException catch (e) {
      throw AccountException(_authMessage(e));
    }
  }

  /// Deletes the backup in the cloud, then the account itself. Call
  /// [reauthenticate] first. Reminders on this phone are removed only if
  /// [removeFromPhone].
  static Future<void> deleteAccount({required bool removeFromPhone}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw const AccountException('You are not signed in.');

    // Stop uploads first, so nothing is written back while deleting.
    await AppServices.reminders.attachAccount(null);
    try {
      await _deleteCloudData(user.uid);
      await user.delete();
    } catch (e) {
      // Still signed in: the next backup must compare everything again,
      // because part of the cloud copy may be gone. Backup stays off for
      // this session; the user is deleting the account.
      await AppServices.reminders.forgetBackupState();
      if (e is AccountException) rethrow;
      if (e is FirebaseAuthException) throw AccountException(_authMessage(e));
      if (e is FirebaseException || e is TimeoutException) {
        throw const AccountException(
          "Couldn't reach the server. Connect to the internet and try again.",
        );
      }
      rethrow;
    }

    await GoogleAuth.signOut();
    if (removeFromPhone) await removeFromThisPhone();
  }

  /// Deletes all reminders and history on this phone and clears their
  /// alarms and notifications.
  static Future<void> removeFromThisPhone() async {
    await AppServices.reminders.wipeDevice();
    await Notifs.cancelAll();
    await ReminderScheduler.rearmNow();
  }

  static Future<void> _deleteCloudData(String uid) async {
    final db = FirebaseFirestore.instance;
    // Reading from the server first means an offline phone stops here,
    // before anything is deleted.
    const server = GetOptions(source: Source.server);

    var deleted = 0;
    for (final path in ['users/$uid/reminders', 'users/$uid/reminderEvents']) {
      final snap = await db
          .collection(path)
          .get(server)
          .timeout(_serverTimeout);
      await _commit(db, [
        for (final doc in snap.docs) (WriteBatch b) => b.delete(doc.reference),
      ]);
      deleted += snap.docs.length;
    }

    // Shared reminders (from older versions): delete the ones this account
    // owns and leave the others.
    final shared = await db
        .collection('sharedReminders')
        .where('participantUids', arrayContains: uid)
        .get(server)
        .timeout(_serverTimeout);
    await _commit(db, [
      for (final doc in shared.docs)
        if (doc.data()['ownerUid'] == uid)
          (WriteBatch b) => b.delete(doc.reference)
        else
          (WriteBatch b) => b.update(doc.reference, {
            'participantUids': FieldValue.arrayRemove([uid]),
          }),
    ]);

    await db.doc('users/$uid').delete().timeout(_serverTimeout);
    debugPrint(
      'Deleted the cloud data: $deleted backup documents, '
      '${shared.docs.length} shared reminders.',
    );
  }

  static Future<void> _commit(
    FirebaseFirestore db,
    List<void Function(WriteBatch)> writes,
  ) async {
    for (var i = 0; i < writes.length; i += _batchSize) {
      final batch = db.batch();
      for (final write in writes.skip(i).take(_batchSize)) {
        write(batch);
      }
      await batch.commit().timeout(_serverTimeout);
    }
  }

  static String _authMessage(FirebaseAuthException e) => switch (e.code) {
    'wrong-password' || 'invalid-credential' => "That password isn't right.",
    'user-mismatch' =>
      "That's a different account. Choose the one you're signed in with.",
    'network-request-failed' =>
      "You're offline. Connect to the internet and try again.",
    'too-many-requests' => 'Too many attempts. Wait a few minutes and retry.',
    'requires-recent-login' => "Please confirm it's you again, then retry.",
    _ => e.message ?? 'Something went wrong (${e.code}).',
  };
}
