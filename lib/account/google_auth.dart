import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Google sign-in failed for a reason worth telling the user about.
class GoogleAuthException implements Exception {
  const GoogleAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The one place that talks to the Google Sign-In plugin (v7, Credential
/// Manager on Android), so plugin changes only touch this file.
///
/// On Android the plugin reads the server client ID from the
/// `default_web_client_id` resource that the google-services Gradle plugin
/// generates from google-services.json.
class GoogleAuth {
  GoogleAuth._();

  static Future<void>? _initializing;

  /// The plugin must be initialized exactly once before any other call. A
  /// failed attempt may be retried.
  static Future<void> _ready() {
    return _initializing ??= GoogleSignIn.instance.initialize().catchError((
      Object e,
    ) {
      _initializing = null;
      throw e;
    });
  }

  /// Shows Google's account picker and returns a Firebase credential, or
  /// null if the user backs out. Throws [GoogleAuthException] otherwise.
  static Future<AuthCredential?> credential() async {
    try {
      await _ready();
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw const GoogleAuthException(
          'Google sign-in failed. Please try again.',
        );
      }
      return GoogleAuthProvider.credential(idToken: idToken);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      debugPrint('Google sign-in failed: ${e.code} ${e.description}');
      throw GoogleAuthException(_message(e.code));
    }
  }

  /// Forgets the chosen Google account, so the picker shows next time.
  static Future<void> signOut() async {
    try {
      await _ready();
      await GoogleSignIn.instance.signOut();
    } catch (e) {
      debugPrint('Google sign-out failed: $e');
    }
  }

  static String _message(GoogleSignInExceptionCode code) => switch (code) {
    GoogleSignInExceptionCode.interrupted =>
      'Google sign-in was interrupted. Please try again.',
    GoogleSignInExceptionCode.uiUnavailable =>
      "Google sign-in couldn't open on this phone. Try email instead.",
    GoogleSignInExceptionCode.userMismatch =>
      "That's a different Google account. Choose the one you're signed in "
          'with.',
    // Usually this build's signing key (SHA-1) isn't registered for the app
    // in Firebase: add it, download google-services.json again, rebuild.
    GoogleSignInExceptionCode.clientConfigurationError ||
    GoogleSignInExceptionCode.providerConfigurationError =>
      "Google sign-in isn't set up for this version of the app. Use email "
          'for now.',
    _ => 'Google sign-in failed. Please try again.',
  };
}
