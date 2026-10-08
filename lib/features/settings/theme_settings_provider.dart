import 'package:flutter/foundation.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 外觀風格與玻璃強度；深淺模式由 [SettingsProvider.themeMode] 決定。
class ThemeSettingsProvider extends ChangeNotifier {
  ThemeSettingsProvider() : _prefs = getIt<SharedPreferences>() {
    style = AppStyle.fromStorage(_prefs.getString(PreferKey.appStyle));
    glassStrength = GlassStrength.fromStorage(
      _prefs.getString(PreferKey.glassStrength),
    );
  }

  final SharedPreferences _prefs;

  /// App 介面、閱讀正文與閱讀選單共用的風格。
  late AppStyle style;

  /// 浮動列、選單等玻璃材質的強度；App 介面與閱讀選單共用。
  late GlassStrength glassStrength;

  void setStyle(AppStyle value) {
    if (style == value) return;
    style = value;
    _prefs.setString(PreferKey.appStyle, value.name);
    notifyListeners();
  }

  void setGlassStrength(GlassStrength value) {
    if (glassStrength == value) return;
    glassStrength = value;
    _prefs.setString(PreferKey.glassStrength, value.name);
    notifyListeners();
  }
}
