import 'package:flutter/foundation.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/shared/navigation/app_page_transition.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';
import 'package:night_reader/shared/widgets/skeleton_reveal.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 外觀風格、玻璃強度、換頁動畫、骨架的樣子與骨架換場；深淺模式由
/// [SettingsProvider.themeMode] 決定。
class ThemeSettingsProvider extends ChangeNotifier {
  ThemeSettingsProvider() : _prefs = getIt<SharedPreferences>() {
    style = AppStyle.fromStorage(_prefs.getString(PreferKey.appStyle));
    accent = AppAccent.fromStorage(_prefs.getString(PreferKey.appAccent));
    glassStrength = GlassStrength.fromStorage(
      _prefs.getString(PreferKey.glassStrength),
    );
    pageTransition = AppPageTransition.fromStorage(
      _prefs.getString(PreferKey.pageTransition),
    );
    final revealMillis = _prefs.getInt(PreferKey.skeletonRevealMillis);
    skeletonReveal = SkeletonReveal(
      style: SkeletonRevealStyle.fromStorage(
        _prefs.getString(PreferKey.skeletonRevealStyle),
      ),
      duration: revealMillis == null
          ? SkeletonReveal.defaultDuration
          : _clampRevealDuration(Duration(milliseconds: revealMillis)),
    );
    skeletonLook = SkeletonLook(
      strength: SkeletonStrength.fromStorage(
        _prefs.getString(PreferKey.skeletonStrength),
      ),
      breath: SkeletonBreath.fromStorage(
        _prefs.getString(PreferKey.skeletonBreath),
      ),
    );
  }

  final SharedPreferences _prefs;

  /// App 介面、閱讀正文與閱讀選單共用的風格。
  late AppStyle style;

  /// 開關、選取與強調按鈕的顏色；預設跟隨風格。
  late AppAccent accent;

  /// 浮動列、選單等玻璃材質的強度；App 介面與閱讀選單共用。
  late GlassStrength glassStrength;

  /// 全 App 換頁共用的轉場。
  late AppPageTransition pageTransition;

  /// 骨架換成內容的方式與時長。
  late SkeletonReveal skeletonReveal;

  /// 骨架的深淺與呼吸方式。
  late SkeletonLook skeletonLook;

  void setStyle(AppStyle value) {
    if (style == value) return;
    style = value;
    _prefs.setString(PreferKey.appStyle, value.name);
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

  void setPageTransition(AppPageTransition value) {
    if (pageTransition == value) return;
    pageTransition = value;
    _prefs.setString(PreferKey.pageTransition, value.name);
    notifyListeners();
  }

  void setSkeletonRevealStyle(SkeletonRevealStyle value) {
    if (skeletonReveal.style == value) return;
    skeletonReveal = skeletonReveal.copyWith(style: value);
    _prefs.setString(PreferKey.skeletonRevealStyle, value.name);
    notifyListeners();
  }

  void setSkeletonRevealDuration(Duration value) {
    final duration = _clampRevealDuration(value);
    if (skeletonReveal.duration == duration) return;
    skeletonReveal = skeletonReveal.copyWith(duration: duration);
    _prefs.setInt(PreferKey.skeletonRevealMillis, duration.inMilliseconds);
    notifyListeners();
  }

  void setSkeletonStrength(SkeletonStrength value) {
    if (skeletonLook.strength == value) return;
    skeletonLook = skeletonLook.copyWith(strength: value);
    _prefs.setString(PreferKey.skeletonStrength, value.name);
    notifyListeners();
  }

  void setSkeletonBreath(SkeletonBreath value) {
    if (skeletonLook.breath == value) return;
    skeletonLook = skeletonLook.copyWith(breath: value);
    _prefs.setString(PreferKey.skeletonBreath, value.name);
    notifyListeners();
  }

  static Duration _clampRevealDuration(Duration value) => Duration(
    milliseconds: value.inMilliseconds.clamp(
      SkeletonReveal.minDuration.inMilliseconds,
      SkeletonReveal.maxDuration.inMilliseconds,
    ),
  );
}
