import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:night_reader/core/config/app_config.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/tts_service.dart';

import 'provider/settings_base.dart';

export 'provider/settings_base.dart';

const String _systemTtsSourceKey = 'system';

Future<void> _applyTtsSettingSafely(
  Future<void> operation,
  String settingName,
) async {
  try {
    await operation;
  } catch (error, stackTrace) {
    // Settings are persisted independently from the optional platform TTS
    // engine.  A rejected platform call must not become an unhandled Future
    // during startup or when the user changes a setting.
    AppLog.e(
      'TTS setting update failed ($settingName): $error',
      error: error,
      stackTrace: stackTrace,
    );
  }
}

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

  // --- 主題與顯示 ---
  bool transparentStatusBar = true;
  bool immNavigationBar = true;

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
    ttsSourceKey = _systemTtsSourceKey;

    // 朗讀參數（語速／音調／音量）由 TTSService 自行保存與還原；
    // 這裡只在啟動後觸發初始化，不阻塞首畫面。
    unawaited(_applyTtsSettingSafely(TTSService().init(), 'init'));
  }

  /// 僅用於清理舊版非 system TTS 書源設定（migration），在建構後非同步執行，不影響 UI 渲染。
  Future<void> _migrateLegacySettings() async {
    final prefs = await SharedPreferences.getInstance();
    final savedTtsSource = prefs.getString(PreferKey.ttsSource);
    if (savedTtsSource != null && savedTtsSource != _systemTtsSourceKey) {
      await prefs.setString(PreferKey.ttsSource, _systemTtsSourceKey);
    }
  }
}
