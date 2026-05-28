import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SettingsProvider 的基礎類別與持久化邏輯
abstract class SettingsProviderBase extends ChangeNotifier {
  ThemeMode themeMode = ThemeMode.system;
  Locale? locale;

  Future<void> save(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is double) {
      await prefs.setDouble(key, value);
    } else if (value is int) {
      await prefs.setInt(key, value);
    } else if (value is String) {
      await prefs.setString(key, value);
    }
  }

  ThemeMode parseThemeMode(String mode) {
    switch (mode) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  Locale? parseLocale(String lang) {
    if (lang == 'system') {
      return null;
    }
    final parts = lang.split('_');
    if (parts.length == 2) {
      return Locale(parts[0], parts[1]);
    }
    return Locale(lang);
  }

  void update() => notifyListeners();
}
