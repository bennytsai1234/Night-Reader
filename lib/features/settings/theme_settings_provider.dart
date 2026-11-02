import 'dart:async';

import 'package:flutter/material.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/fonts/app_font.dart';
import 'package:night_reader/core/fonts/font_library.dart';
import 'package:night_reader/core/sync/settings_sync.dart';
import 'package:night_reader/shared/navigation/app_page_transition.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 外觀風格、強調色、玻璃強度與換頁動畫；深淺模式由
/// [SettingsProvider.themeMode] 決定，淺色與深色各用自己選的風格。
class ThemeSettingsProvider extends ChangeNotifier {
  ThemeSettingsProvider() : _prefs = getIt<SharedPreferences>() {
    final shared = _prefs.getString(PreferKey.sharedStyle);
    if (shared != null) {
      // 淺深共用一個風格時選的：升級後兩邊都沿用，畫面不變。讀完就刪，
      // 之後只會在還原舊版備份時再出現，那時以備份為準蓋過兩邊。
      _prefs.setString(PreferKey.lightStyle, shared);
      _prefs.setString(PreferKey.darkStyle, shared);
      _prefs.remove(PreferKey.sharedStyle);
    }
    _load();
    SettingsSync.applied.addListener(_reload);
    _shownUiFontFamily = uiFontFamily;
    FontLibrary.instance.changes.addListener(_onFontsChanged);
  }

  /// 主題目前用的介面字族；有字型下載好時只在它變了才重建整個 App（正文字型
  /// 下載好不影響介面）。
  String? _shownUiFontFamily;

  void _onFontsChanged() {
    final family = uiFontFamily;
    if (family == _shownUiFontFamily) return;
    _shownUiFontFamily = family;
    notifyListeners();
  }

  void _load() {
    lightStyle = AppStyle.fromStorage(
      _prefs.getString(PreferKey.lightStyle),
      fallback: defaultLightStyle,
    );
    darkStyle = AppStyle.fromStorage(
      _prefs.getString(PreferKey.darkStyle),
      fallback: defaultDarkStyle,
    );
    pureBlack = _prefs.getBool(PreferKey.pureBlack) ?? true;
    accent = AppAccent.fromStorage(_prefs.getString(PreferKey.appAccent));
    glassStrength = GlassStrength.fromStorage(
      _prefs.getString(PreferKey.glassStrength),
    );
    pageTransition = AppPageTransition.fromStorage(
      _prefs.getString(PreferKey.pageTransition),
    );
    uiFont = AppFont.fromStorage(_prefs.getString(PreferKey.uiFont));
    // 另一台選了這台還沒下載的字型：在背景下載，好了再換上。
    unawaited(FontLibrary.instance.ensure(uiFont));
  }

  /// 同步套用了另一台的設定。
  void _reload() {
    _load();
    _shownUiFontFamily = uiFontFamily;
    notifyListeners();
  }

  @override
  void dispose() {
    SettingsSync.applied.removeListener(_reload);
    FontLibrary.instance.changes.removeListener(_onFontsChanged);
    super.dispose();
  }

  static const AppStyle defaultLightStyle = AppStyle.paper;
  static const AppStyle defaultDarkStyle = AppStyle.plain;

  final SharedPreferences _prefs;

  /// 淺色時 App 介面、閱讀正文與閱讀選單共用的風格。
  late AppStyle lightStyle;

  /// 深色時用的風格。
  late AppStyle darkStyle;

  /// 深色時頁面與閱讀紙一律純黑（[StylePalette.toPureBlack]）。
  late bool pureBlack;

  /// 開關、選取與強調按鈕的顏色；預設跟隨風格。
  late AppAccent accent;

  /// 浮動列、選單等玻璃材質的強度；App 介面與閱讀選單共用。
  late GlassStrength glassStrength;

  /// 全 App 換頁共用的轉場。
  late AppPageTransition pageTransition;

  /// App 介面的字型（ADR 0045）；閱讀正文另外選。
  late AppFont uiFont;

  /// 介面目前用的字族；選的字型還不能用時是 null（系統字型）。
  String? get uiFontFamily => FontLibrary.instance.familyOf(uiFont);

  AppStyle styleFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkStyle : lightStyle;

  /// 這個深淺實際套用的配色（含強調色與純黑）。
  StylePalette paletteFor(Brightness brightness) =>
      styleFor(brightness).paletteFor(brightness, accent, pureBlack: pureBlack);

  void setStyle(Brightness brightness, AppStyle value) {
    if (styleFor(brightness) == value) return;
    if (brightness == Brightness.dark) {
      darkStyle = value;
      _prefs.setString(PreferKey.darkStyle, value.name);
    } else {
      lightStyle = value;
      _prefs.setString(PreferKey.lightStyle, value.name);
    }
    notifyListeners();
  }

  void setPureBlack(bool value) {
    if (pureBlack == value) return;
    pureBlack = value;
    _prefs.setBool(PreferKey.pureBlack, value);
    notifyListeners();
  }

  void setAccent(AppAccent value) {
    if (accent == value) return;
    accent = value;
    _prefs.setString(PreferKey.appAccent, value.name);
    notifyListeners();
  }

  void setGlassStrength(GlassStrength value) {
    if (glassStrength == value) return;
    glassStrength = value;
    _prefs.setString(PreferKey.glassStrength, value.name);
    notifyListeners();
  }

  /// 選了還沒下載的字型就開始下載，好了才換上（[FontLibrary.changes]）。
  void setUiFont(AppFont value) {
    if (uiFont == value) return;
    uiFont = value;
    _prefs.setString(PreferKey.uiFont, value.id);
    unawaited(FontLibrary.instance.ensure(value));
    _shownUiFontFamily = uiFontFamily;
    notifyListeners();
  }

  void setPageTransition(AppPageTransition value) {
    if (pageTransition == value) return;
    pageTransition = value;
    _prefs.setString(PreferKey.pageTransition, value.name);
    notifyListeners();
  }
}
