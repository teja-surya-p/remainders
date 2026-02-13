import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UserScope {
  UserScope._();

  static String key(User user) => user.uid;

  static CollectionReference<Map<String, dynamic>> remindersRef(User user) {
    return FirebaseFirestore.instance.collection('users/${user.uid}/reminders');
  }

  static CollectionReference<Map<String, dynamic>> eventsRef(User user) {
    return FirebaseFirestore.instance.collection(
      'users/${user.uid}/reminderEvents',
    );
  }

  static DocumentReference<Map<String, dynamic>> reminderDoc(
    User user,
    String reminderId,
  ) {
    return FirebaseFirestore.instance.doc(
      'users/${user.uid}/reminders/$reminderId',
    );
  }

  static Future<void> migrateUidToEmail(User user) async {
    final emailRaw = user.email;
    final email = emailRaw?.toLowerCase();
    if (email == null || email.isEmpty) return;

    final uidRef = FirebaseFirestore.instance.collection(
      'users/${user.uid}/reminders',
    );

    final oldEmailRef = FirebaseFirestore.instance.collection(
      'users/$email/reminders',
    );
    final oldEmailSnap = await oldEmailRef.get();
    for (final doc in oldEmailSnap.docs) {
      await uidRef.doc(doc.id).set(doc.data(), SetOptions(merge: true));
      await doc.reference.delete();
    }

    if (emailRaw != email) {
      final oldCaseRef = FirebaseFirestore.instance.collection(
        'users/$emailRaw/reminders',
      );
      final oldCaseSnap = await oldCaseRef.get();
      for (final doc in oldCaseSnap.docs) {
        await uidRef.doc(doc.id).set(doc.data(), SetOptions(merge: true));
        await doc.reference.delete();
      }
    }
  }
}
