import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemeSetting { system, light, dark }

class ThemeService extends ChangeNotifier {
  static const String _kThemeSetting = 'app_theme_setting';

  SharedPreferences? _prefs;
  AppThemeSetting _setting = AppThemeSetting.system;

  AppThemeSetting get setting => _setting;

  ThemeMode get themeMode {
    switch (_setting) {
      case AppThemeSetting.system:
        return ThemeMode.system;
      case AppThemeSetting.light:
        return ThemeMode.light;
      case AppThemeSetting.dark:
        return ThemeMode.dark;
    }
  }

  Future<void> initialize() async {
    _prefs ??= await SharedPreferences.getInstance();
    final raw = _prefs!.getString(_kThemeSetting);
    _setting = _fromStorage(raw);
    notifyListeners();
  }

  Future<void> setThemeSetting(AppThemeSetting next) async {
    if (_setting == next) return;
    _setting = next;
    notifyListeners();

    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_kThemeSetting, _toStorage(next));
  }

  String label(AppThemeSetting value) {
    switch (value) {
      case AppThemeSetting.system:
        return 'System';
      case AppThemeSetting.light:
        return 'Light';
      case AppThemeSetting.dark:
        return 'Dark';
    }
  }

  static String _toStorage(AppThemeSetting value) {
    switch (value) {
      case AppThemeSetting.system:
        return 'system';
      case AppThemeSetting.light:
        return 'light';
      case AppThemeSetting.dark:
        return 'dark';
    }
  }

  static AppThemeSetting _fromStorage(String? value) {
    switch (value) {
      case 'light':
        return AppThemeSetting.light;
      case 'dark':
        return AppThemeSetting.dark;
      default:
        return AppThemeSetting.system;
    }
  }
}
