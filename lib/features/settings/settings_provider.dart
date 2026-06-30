import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:night_reader/core/config/app_config.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/services/tts_service.dart';
import 'provider/settings_base.dart';

export 'provider/settings_base.dart';

const String _systemTtsSourceKey = 'system';

/// SettingsProvider - 設置提供者 (重構後)
/// (原 Android help/config/AppConfig.kt)
class SettingsProvider extends SettingsProviderBase {
  bool appCrash = false;
  int lastBackup = 0;
  int lastVersionCode = 0;
  bool privacyAgreed = false;

  // 封面進階設定
  int coverSearchPriority = 0;
  int coverTimeout = 5000;
  String globalCoverRule = '';

  // --- 主題色彩設定 ---
  bool transparentStatusBar = true;
  bool immNavigationBar = true;
  Color dayPrimaryColor = Colors.brown;
  Color dayAccentColor = Colors.red;
  Color dayBackgroundColor = Colors.grey.shade100;
  Color dayBottomBackgroundColor = Colors.grey.shade200;
  Color nightPrimaryColor = Colors.blueGrey.shade600;
  Color nightAccentColor = Colors.deepOrange.shade800;
  Color nightBackgroundColor = Colors.grey.shade900;
  Color nightBottomBackgroundColor = Colors.grey.shade800;
  String dayBackgroundImage = '';
  String nightBackgroundImage = '';

  // --- 閱讀設定 ---
  bool hideStatusBar = false;
  bool hideNavigationBar = false;
  bool readBodyToLh = true;
  bool paddingDisplayCutouts = false;
  bool useZhLayout = false;
  bool textBottomJustify = true;
  bool mouseWheelPage = true;
  bool keyPageOnLongPress = false;
  bool showBrightnessView = true;
  bool noAnimScrollPage = false;
  bool previewImageByClick = false;
  bool optimizeRender = false;
  bool disableReturnKey = false;
  bool expandTextMenu = false;

  // --- 朗讀設定 ---
  bool ignoreAudioFocusAloud = false;
  bool pauseReadAloudWhilePhoneCalls = false;
  bool readAloudWakeLock = false;
  bool systemMediaControlCompatibilityChange = false;
  bool mediaButtonPerNext = false;
  bool readAloudByPage = false;
  bool streamReadAloudAudio = false;
  double speechRate = 1.0;
  double speechPitch = 1.0;
  double speechVolume = 1.0;
  String ttsSourceKey = _systemTtsSourceKey;

  // 其他
  bool recordLog = false;

  // --- 缺失屬性補全 ---
  bool autoRefresh = true;
  bool defaultToRead = false;
  int threadCount = 4;
  String userAgent = '';
  bool antiAlias = true;
  bool replaceEnableDefault = true;
  bool enableCronet = false;
  String bookStorageDir = '';
  bool ignoreAudioFocus = false;
  bool autoClearExpired = true;
  bool mediaButtonOnExit = true;
  bool readAloudByMediaButton = false;
  bool showMangaUi = true;

  void setUserAgent(String v) {
    userAgent = v;
    save(PreferKey.userAgent, v);
    update();
  }

  void setReplaceEnableDefault(bool v) {
    replaceEnableDefault = v;
    AppConfig.replaceEnableDefault = v;
    save(PreferKey.replaceEnableDefault, v);
    update();
  }

  SettingsProvider() {
    _loadFromPrefs(getIt<SharedPreferences>());
    unawaited(_migrateLegacySettings());
  }

  /// 從已預載的 SharedPreferences 同步讀取所有設定，在建構子第一幀前完成，消除啟動閃爍。
  void _loadFromPrefs(SharedPreferences prefs) {
    // --- 核心設定 ---
    themeMode = parseThemeMode(
      prefs.getString(PreferKey.themeMode) ?? 'system',
    );
    locale = parseLocale(prefs.getString(PreferKey.language) ?? 'system');
    userAgent = prefs.getString(PreferKey.userAgent) ?? '';
    threadCount = prefs.getInt(PreferKey.threadCount) ?? 4;
    recordLog = prefs.getBool(PreferKey.recordLog) ?? false;
    appCrash = prefs.getBool(PreferKey.appCrash) ?? false;
    lastVersionCode = prefs.getInt(PreferKey.lastVersionCode) ?? 0;
    privacyAgreed = prefs.getBool(PreferKey.privacyAgreed) ?? false;

    // --- 封面進階設定 ---
    coverSearchPriority = prefs.getInt(PreferKey.coverSearchPriority) ?? 0;
    coverTimeout = prefs.getInt(PreferKey.coverTimeout) ?? 5000;
    globalCoverRule = prefs.getString(PreferKey.globalCoverRule) ?? '';

    lastBackup = prefs.getInt(PreferKey.lastBackup) ?? 0;

    // --- 主題與顯示 ---
    transparentStatusBar =
        prefs.getBool(PreferKey.transparentStatusBar) ?? true;
    immNavigationBar = prefs.getBool(PreferKey.immNavigationBar) ?? true;
    dayBackgroundImage = prefs.getString(PreferKey.bgImage) ?? '';
    nightBackgroundImage = prefs.getString(PreferKey.bgImageN) ?? '';
    dayPrimaryColor = Color(
      prefs.getInt(PreferKey.cPrimary) ?? Colors.brown.toARGB32(),
    );
    dayAccentColor = Color(
      prefs.getInt(PreferKey.cAccent) ?? Colors.red.toARGB32(),
    );
    dayBackgroundColor = Color(
      prefs.getInt(PreferKey.cBackground) ?? Colors.grey.shade100.toARGB32(),
    );
    dayBottomBackgroundColor = Color(
      prefs.getInt(PreferKey.cBBackground) ?? Colors.grey.shade200.toARGB32(),
    );
    nightPrimaryColor = Color(
      prefs.getInt(PreferKey.cNPrimary) ?? Colors.blueGrey.shade600.toARGB32(),
    );
    nightAccentColor = Color(
      prefs.getInt(PreferKey.cNAccent) ?? Colors.deepOrange.shade800.toARGB32(),
    );
    nightBackgroundColor = Color(
      prefs.getInt(PreferKey.cNBackground) ?? Colors.grey.shade900.toARGB32(),
    );
    nightBottomBackgroundColor = Color(
      prefs.getInt(PreferKey.cNBBackground) ?? Colors.grey.shade800.toARGB32(),
    );

    // --- 閱讀設定 ---
    hideStatusBar = prefs.getBool(PreferKey.hideStatusBar) ?? false;
    hideNavigationBar = prefs.getBool(PreferKey.hideNavigationBar) ?? false;
    readBodyToLh = prefs.getBool(PreferKey.readBodyToLh) ?? true;
    paddingDisplayCutouts =
        prefs.getBool(PreferKey.paddingDisplayCutouts) ?? false;
    useZhLayout = prefs.getBool(PreferKey.useZhLayout) ?? false;
    textBottomJustify = prefs.getBool(PreferKey.textBottomJustify) ?? true;
    mouseWheelPage = prefs.getBool(PreferKey.mouseWheelPage) ?? true;
    keyPageOnLongPress = prefs.getBool(PreferKey.keyPageOnLongPress) ?? false;
    showBrightnessView = prefs.getBool(PreferKey.showBrightnessView) ?? true;
    noAnimScrollPage = prefs.getBool(PreferKey.noAnimScrollPage) ?? false;
    previewImageByClick = prefs.getBool(PreferKey.previewImageByClick) ?? false;
    optimizeRender = prefs.getBool(PreferKey.optimizeRender) ?? false;
    expandTextMenu = prefs.getBool(PreferKey.expandTextMenu) ?? false;
    autoRefresh = prefs.getBool(PreferKey.autoRefresh) ?? true;
    defaultToRead = prefs.getBool(PreferKey.defaultToRead) ?? false;
    replaceEnableDefault =
        prefs.getBool(PreferKey.replaceEnableDefault) ?? true;
    AppConfig.replaceEnableDefault = replaceEnableDefault;
    autoClearExpired = prefs.getBool(PreferKey.autoClearExpired) ?? true;
    showMangaUi = prefs.getBool(PreferKey.showMangaUi) ?? true;
    antiAlias = prefs.getBool(PreferKey.antiAlias) ?? true;

    // --- 朗讀設定 ---
    ignoreAudioFocus = prefs.getBool(PreferKey.ignoreAudioFocus) ?? false;
    ignoreAudioFocusAloud =
        prefs.getBool(PreferKey.ignoreAudioFocusAloud) ?? false;
    pauseReadAloudWhilePhoneCalls =
        prefs.getBool(PreferKey.pauseReadAloudWhilePhoneCalls) ?? false;
    readAloudWakeLock = prefs.getBool(PreferKey.readAloudWakeLock) ?? false;
    readAloudByPage = prefs.getBool(PreferKey.readAloudByPage) ?? false;
    streamReadAloudAudio =
        prefs.getBool(PreferKey.streamReadAloudAudio) ?? false;
    readAloudByMediaButton =
        prefs.getBool(PreferKey.readAloudByMediaButton) ?? false;
    speechRate = prefs.getDouble(PreferKey.ttsSpeechRate) ?? 1.0;
    speechPitch = prefs.getDouble(PreferKey.speechPitch) ?? 1.0;
    speechVolume = prefs.getDouble(PreferKey.speechVolume) ?? 1.0;
    ttsSourceKey = _systemTtsSourceKey;

    TTSService().setRate(speechRate);
    TTSService().setPitch(speechPitch);
    TTSService().setVolume(speechVolume);
  }

  /// 僅用於清理舊版非 system TTS 書源設定（migration），在建構後非同步執行，不影響 UI 渲染。
  Future<void> _migrateLegacySettings() async {
    final prefs = await SharedPreferences.getInstance();
    final savedTtsSource = prefs.getString(PreferKey.ttsSource);
    if (savedTtsSource != null && savedTtsSource != _systemTtsSourceKey) {
      await prefs.setString(PreferKey.ttsSource, _systemTtsSourceKey);
    }
  }

  // --- 朗讀速率 ---
  void setSpeechRate(double v) {
    speechRate = v;
    TTSService().setRate(v);
    save(PreferKey.ttsSpeechRate, v);
    update();
  }

  void setSpeechPitch(double v) {
    speechPitch = v;
    TTSService().setPitch(v);
    save(PreferKey.speechPitch, v);
    update();
  }

  void setSpeechVolume(double v) {
    speechVolume = v;
    TTSService().setVolume(v);
    save(PreferKey.speechVolume, v);
    update();
  }
}
