import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/shared/theme/app_theme.dart';
import 'package:night_reader/shared/theme/theme_customization.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeSettingsProvider extends ChangeNotifier {
  ThemeSettingsProvider() : _prefs = getIt<SharedPreferences>() {
    appLight = _readApp(_kAppLight, AppUiThemeColors.lightDefault);
    appDark = _readApp(_kAppDark, AppUiThemeColors.darkDefault);
    readerLight = _readArea(_kReaderLight, ReaderAreaThemeColors.contentLightDefault);
    readerDark = _readArea(_kReaderDark, ReaderAreaThemeColors.contentDarkDefault);
    menuLight = _readArea(_kMenuLight, ReaderAreaThemeColors.menuLightDefault);
    menuDark = _readArea(_kMenuDark, ReaderAreaThemeColors.menuDarkDefault);
    appLightCustom = _prefs.getBool(_kAppLightCustom) ?? false;
    appDarkCustom = _prefs.getBool(_kAppDarkCustom) ?? false;
    readerLightCustom = _prefs.getBool(_kReaderLightCustom) ?? false;
    readerDarkCustom = _prefs.getBool(_kReaderDarkCustom) ?? false;
    menuLightCustom = _prefs.getBool(_kMenuLightCustom) ?? false;
    menuDarkCustom = _prefs.getBool(_kMenuDarkCustom) ?? false;
  }

  static const _kAppLight = 'theme_app_light_custom_v1';
  static const _kAppDark = 'theme_app_dark_custom_v1';
  static const _kReaderLight = 'theme_reader_light_custom_v1';
  static const _kReaderDark = 'theme_reader_dark_custom_v1';
  static const _kMenuLight = 'theme_menu_light_custom_v1';
  static const _kMenuDark = 'theme_menu_dark_custom_v1';
  static const _kAppLightCustom = 'theme_app_light_use_custom';
  static const _kAppDarkCustom = 'theme_app_dark_use_custom';
  static const _kReaderLightCustom = 'theme_reader_light_use_custom';
  static const _kReaderDarkCustom = 'theme_reader_dark_use_custom';
  static const _kMenuLightCustom = 'theme_menu_light_use_custom';
  static const _kMenuDarkCustom = 'theme_menu_dark_use_custom';
  static const _kMenuDayIndex = 'theme_menu_day_builtin_index';
  static const _kMenuNightIndex = 'theme_menu_night_builtin_index';

  final SharedPreferences _prefs;

  late AppUiThemeColors appLight;
  late AppUiThemeColors appDark;
  late ReaderAreaThemeColors readerLight;
  late ReaderAreaThemeColors readerDark;
  late ReaderAreaThemeColors menuLight;
  late ReaderAreaThemeColors menuDark;
  late bool appLightCustom;
  late bool appDarkCustom;
  late bool readerLightCustom;
  late bool readerDarkCustom;
  late bool menuLightCustom;
  late bool menuDarkCustom;

  AppUiThemeColors get effectiveAppLight => appLightCustom ? appLight : AppUiThemeColors.lightDefault;
  AppUiThemeColors get effectiveAppDark => appDarkCustom ? appDark : AppUiThemeColors.darkDefault;

  void setUseCustom(ThemeArea area, bool dark, bool value) {
    final key = switch ((area, dark)) {
      (ThemeArea.app, false) => _kAppLightCustom,
      (ThemeArea.app, true) => _kAppDarkCustom,
      (ThemeArea.reader, false) => _kReaderLightCustom,
      (ThemeArea.reader, true) => _kReaderDarkCustom,
      (ThemeArea.menu, false) => _kMenuLightCustom,
      (ThemeArea.menu, true) => _kMenuDarkCustom,
    };
    switch ((area, dark)) {
      case (ThemeArea.app, false):
        appLightCustom = value;
        break;
      case (ThemeArea.app, true):
        appDarkCustom = value;
        break;
      case (ThemeArea.reader, false):
        readerLightCustom = value;
        break;
      case (ThemeArea.reader, true):
        readerDarkCustom = value;
        break;
      case (ThemeArea.menu, false):
        menuLightCustom = value;
        break;
      case (ThemeArea.menu, true):
        menuDarkCustom = value;
        break;
    }
    _prefs.setBool(key, value);
    notifyListeners();
  }

  void updateApp(bool dark, AppUiThemeColors colors) {
    if (dark) {
      appDark = colors;
      _prefs.setString(_kAppDark, jsonEncode(colors.toJson()));
    } else {
      appLight = colors;
      _prefs.setString(_kAppLight, jsonEncode(colors.toJson()));
    }
    notifyListeners();
  }

  void updateArea(ThemeArea area, bool dark, ReaderAreaThemeColors colors) {
    final key = switch ((area, dark)) {
      (ThemeArea.reader, false) => _kReaderLight,
      (ThemeArea.reader, true) => _kReaderDark,
      (ThemeArea.menu, false) => _kMenuLight,
      (ThemeArea.menu, true) => _kMenuDark,
      _ => throw ArgumentError('App theme must use updateApp'),
    };
    if (area == ThemeArea.reader) {
      if (dark) {
        readerDark = colors;
      } else {
        readerLight = colors;
      }
    } else {
      if (dark) {
        menuDark = colors;
      } else {
        menuLight = colors;
      }
    }
    _prefs.setString(key, jsonEncode(colors.toJson()));
    notifyListeners();
  }

  void reset(ThemeArea area, bool dark) {
    switch (area) {
      case ThemeArea.app:
        updateApp(dark, dark ? AppUiThemeColors.darkDefault : AppUiThemeColors.lightDefault);
        return;
      case ThemeArea.reader:
        updateArea(area, dark, dark ? ReaderAreaThemeColors.contentDarkDefault : ReaderAreaThemeColors.contentLightDefault);
        return;
      case ThemeArea.menu:
        updateArea(area, dark, dark ? ReaderAreaThemeColors.menuDarkDefault : ReaderAreaThemeColors.menuLightDefault);
        return;
    }
  }

  AppUiThemeColors _readApp(String key, AppUiThemeColors fallback) {
    final value = _readJson(key);
    return value == null ? fallback : AppUiThemeColors.fromJson(value, fallback: fallback);
  }

  ReaderAreaThemeColors _readArea(String key, ReaderAreaThemeColors fallback) {
    final value = _readJson(key);
    return value == null ? fallback : ReaderAreaThemeColors.fromJson(value, fallback: fallback);
  }

  Map<String, dynamic>? _readJson(String key) {
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final value = jsonDecode(raw);
      return value is Map<String, dynamic> ? value : null;
    } catch (_) {
      return null;
    }
  }

  static SharedPreferences? _registeredPrefs() {
    if (!getIt.isRegistered<SharedPreferences>()) return null;
    return getIt<SharedPreferences>();
  }

  static ReaderAreaThemeColors? resolveReaderAreaColors({
    required bool dark,
    required bool menu,
  }) {
    final prefs = _registeredPrefs();
    if (prefs == null) return null;
    final useCustom = prefs.getBool(
          menu
              ? (dark ? _kMenuDarkCustom : _kMenuLightCustom)
              : (dark ? _kReaderDarkCustom : _kReaderLightCustom),
        ) ??
        false;
    if (!useCustom) return null;
    final key = menu
        ? (dark ? _kMenuDark : _kMenuLight)
        : (dark ? _kReaderDark : _kReaderLight);
    final fallback = menu
        ? (dark ? ReaderAreaThemeColors.menuDarkDefault : ReaderAreaThemeColors.menuLightDefault)
        : (dark ? ReaderAreaThemeColors.contentDarkDefault : ReaderAreaThemeColors.contentLightDefault);
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return fallback;
    try {
      final value = jsonDecode(raw);
      if (value is Map<String, dynamic>) {
        return ReaderAreaThemeColors.fromJson(value, fallback: fallback);
      }
    } catch (_) {}
    return fallback;
  }

  static ReadingTheme resolveReaderTheme({
    required bool dark,
    required bool menu,
    required ReadingTheme fallback,
  }) {
    final colors = resolveReaderAreaColors(dark: dark, menu: menu);
    if (colors == null) return fallback;
    return ReadingTheme(
      name: dark ? '自訂夜間' : '自訂日間',
      backgroundColor: colors.background,
      textColor: colors.text,
    );
  }

  static int menuBuiltInIndex(bool dark, int fallback) {
    final prefs = _registeredPrefs();
    if (prefs == null) return fallback;
    return prefs.getInt(dark ? _kMenuNightIndex : _kMenuDayIndex) ?? fallback;
  }

  static void saveMenuBuiltInIndex(bool dark, int value) {
    final prefs = _registeredPrefs();
    if (prefs == null) return;
    prefs.setInt(dark ? _kMenuNightIndex : _kMenuDayIndex, value);
  }
}

enum ThemeArea { app, reader, menu }
