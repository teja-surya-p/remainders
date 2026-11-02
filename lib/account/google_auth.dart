import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// The one place that talks to the Google Sign-In plugin, so moving to a new
/// plugin version only changes this file.
class GoogleAuth {
  GoogleAuth._();

  /// Shows Google's account picker and returns a Firebase credential, or
  /// null if the user backs out.
  static Future<AuthCredential?> credential() async {
    final account = await GoogleSignIn().signIn();
    if (account == null) return null;
    final auth = await account.authentication;
    return GoogleAuthProvider.credential(
      accessToken: auth.accessToken,
      idToken: auth.idToken,
    );
  }

  /// Forgets the chosen Google account, so the picker shows next time.
  static Future<void> signOut() async {
    try {
      await GoogleSignIn().signOut();
    } catch (e) {
      debugPrint('Google sign-out failed: $e');
    }
  }
}
