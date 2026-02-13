import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserStore {
  UserStore._();

  static const _kUid = 'user_uid';
  static const _kEmail = 'user_email';
  static const _kName = 'user_name';
  static const _kPhoto = 'user_photo';

  static Future<void> saveUser(User user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUid, user.uid);
    if (user.email != null) {
      await prefs.setString(_kEmail, user.email!);
    }
    if (user.displayName != null) {
      await prefs.setString(_kName, user.displayName!);
    }
    if (user.photoURL != null) {
      await prefs.setString(_kPhoto, user.photoURL!);
    }
  }

  static Future<String?> lastEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kEmail);
  }

  static Future<Map<String, String?>> lastUser() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'uid': prefs.getString(_kUid),
      'email': prefs.getString(_kEmail),
      'name': prefs.getString(_kName),
      'photo': prefs.getString(_kPhoto),
    };
  }
}
