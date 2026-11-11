import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

import 'core/constant/prefer_key.dart';
import 'core/fonts/app_font.dart';
import 'core/fonts/font_library.dart';
import 'core/services/chinese_display.dart';
import 'core/di/injection.dart';
import 'core/database/dao/book_dao.dart';
import 'core/storage/app_storage_paths.dart';
import 'core/storage/reader_layout_cache.dart';
import 'app_providers.dart';
import 'shared/layout/tablet_text_scale.dart';
import 'shared/theme/app_chrome.dart';
import 'shared/theme/app_style.dart';
import 'shared/theme/app_tokens.dart';
import 'shared/theme/custom_app_theme.dart';
import 'shared/navigation/app_page_transition.dart';
import 'shared/navigation/app_route_observer.dart';
import 'shared/navigation/status_bar.dart';
import 'shared/widgets/theme_reveal_scope.dart';
import 'features/association/association_handler_service.dart';
import 'features/settings/launch_screen_theme_sync.dart';
import 'features/settings/settings_provider.dart';
import 'features/settings/theme_settings_provider.dart';
import 'features/welcome/main_page.dart';
import 'features/welcome/startup_failure_panel.dart';
import 'core/engine/source_isolate/source_isolate.dart';
import 'core/network/cloudflare.dart';
import 'core/services/webview_cloudflare_solver.dart';
import 'core/services/app_log_service.dart';
import 'core/services/book_storage_service.dart';
import 'core/services/crash_handler.dart';
import 'core/startup/startup_retry_gate.dart';
import 'features/search/search_provider.dart';
import 'shared/widgets/skeleton_text.dart';
import 'shared/navigation/root_navigator.dart';

Future<bool> runBackgroundTask<T>({
  required Future<void> Function() initialize,
  required Future<List<T>> Function() loadBookshelf,
  required void Function(String message) logInfo,
}) async {
  try {
    await initialize();
    final books = await loadBookshelf();
    logInfo('Background Task: Checking updates for ${books.length} books');
    return true;
  } catch (_) {
    return false;
  }
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  // This entry point is kept for Workmanager background execution. The
  // foreground app deliberately does not call Workmanager.initialize on
  // every first frame: there are currently no registered background tasks,
  // and Android/vivo can spend several seconds creating WorkManager's native
  // database on the UI path.
  Workmanager().executeTask((task, inputData) async {
    return runBackgroundTask(
      initialize: configureDependencies,
      loadBookshelf: () => getIt<BookDao>().getInBookshelf(),
      logInfo: (message) => getIt<Logger>().i(message),
    );
  });
}

final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
const String kAppDisplayName = '夜讀';
final StartupRetryGate _startupRetryGate = StartupRetryGate();

/// 內建標點字型 NightReaderPunct 的 SIL OFL 授權，列在「開源授權」頁。
Stream<LicenseEntry> _punctFontLicense() async* {
  yield LicenseEntryWithLineBreaks(const <String>[
    'NightReaderPunct (Noto Sans CJK TC)',
  ], await rootBundle.loadString('assets/fonts/OFL.txt'));
}

bool _punctLicenseRegistered = false;

void main() {
  runZonedGuarded(_startApp, (error, stack) {
    AppLog.e('Uncaught Error: $error', error: error, stackTrace: stack);
    CrashHandler.recordError(error, stack);
  });
}

Future<void> _startApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  GestureBinding.instance.resamplingEnabled = true;
  AppLog.i('WidgetsFlutterBinding Initialized');
  // 啟動失敗後的重試會再跑一次 _startApp；授權只註冊一次，授權頁才不會重複。
  if (!_punctLicenseRegistered) {
    LicenseRegistry.addLicense(_punctFontLicense);
    _punctLicenseRegistered = true;
  }
  // 書源工作都在書源 isolate 執行。背景下載的 Workmanager 入口不開，維持
  // 原地執行。
  SourceIsolate.enabled = true;
  // Cloudflare 的瀏覽器檢查交給看不到的瀏覽器通過（[HiddenWebViews]）。
  CloudflareClearance.solver = WebViewCloudflareSolver();

  ErrorWidget.builder = (FlutterErrorDetails details) {
    AppLog.e(
      'Rendering Error: ${details.exception}',
      error: details.exception,
      stackTrace: details.stack,
    );
    CrashHandler.recordFlutterError(details);
    return buildFlutterErrorWidget(details);
  };

  try {
    AppLog.i('Configuring Dependencies...');
    await configureDependencies();
    AppLog.i('Dependencies Configured Successfully');

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      AppLog.e(
        'Flutter Error: ${details.exception}',
        error: details.exception,
        stackTrace: details.stack,
      );
      CrashHandler.recordFlutterError(details);
    };

    AppLog.i('$kAppDisplayName Ready to Run');

    // 選了下載的字型（ADR 0045）而且已經下載過：第一幀前註冊好，開 App 就是
    // 這套字，不會先畫系統字型再換。還沒下載的在背景下載。讀不到也照樣開。
    try {
      final prefs = getIt<SharedPreferences>();
      await FontLibrary.instance.start([
        AppFont.fromStorage(prefs.getString(PreferKey.uiFont)),
        AppFont.fromStorage(prefs.getString(PreferKey.readerFont)),
      ]);
    } catch (error, stack) {
      AppLog.e('字型載入失敗: $error', error: error, stackTrace: stack);
    }

    // 第一幀前定下書名的繁簡轉換模式；字典在背景載入，書架等它好了才換場。
    unawaited(ChineseDisplay.start(getIt<SharedPreferences>()));
    _restoreWebViewUserAgent(getIt<SharedPreferences>());
    // 開 App 的骨架照上次量的標點位置畫長條。
    PunctuationInk.restore(getIt<SharedPreferences>());

    runApp(
      MultiProvider(
        providers: AppProviders.providers,
        child: const LaunchScreenThemeSync(child: ReaderApp()),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_runPostFirstFrameStartupTasks());
    });
  } catch (e, stack) {
    AppLog.e('Startup Critical Error: $e', error: e, stackTrace: stack);
    CrashHandler.recordError(e, stack);
    runApp(_StartupFailureApp(error: e, stackTrace: stack));
  }
}

Widget buildFlutterErrorWidget(FlutterErrorDetails details) {
  // 會被換進任何位置（清單列、Row、整個 App），所以不能撐滿上層：在沒有
  // 上限的方向限制大小，也不依賴主題或 Directionality。詳情已記到 AppLog 與
  // CrashHandler，畫面上只放一句說明。
  return Directionality(
    textDirection: TextDirection.ltr,
    child: LimitedBox(
      maxWidth: 360,
      maxHeight: 120,
      child: ColoredBox(
        color: AppPalette.ink500,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Text(
              kDebugMode ? '這部分無法顯示：${details.exception}' : '這部分無法顯示',
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppPalette.ink50, fontSize: 13),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _retryCriticalStartup() {
  return _startupRetryGate.run(
    reset: () async {
      try {
        await getIt.reset();
      } catch (e, stack) {
        AppLog.e('Dependency reset failed: $e', error: e, stackTrace: stack);
      }
    },
    start: _startApp,
  );
}

class _StartupFailureApp extends StatelessWidget {
  const _StartupFailureApp({required this.error, required this.stackTrace});

  final Object error;
  final StackTrace stackTrace;

  @override
  Widget build(BuildContext context) {
    final details = '$error\n\n$stackTrace';
    // 偏好設定可能也讀不到：照沒設定過時的外觀，接在純黑的啟動畫面後面，
    // 不要落回 Material 預設紫。
    return MaterialApp(
      title: kAppDisplayName,
      debugShowCheckedModeBanner: false,
      themeMode: SettingsProviderBase.defaultThemeMode,
      theme: buildAppTheme(
        ThemeSettingsProvider.defaultLightStyle,
        Brightness.light,
        glassStrength: GlassStrength.defaultStrength,
        accent: AppAccent.defaultAccent,
      ),
      darkTheme: buildAppTheme(
        ThemeSettingsProvider.defaultDarkStyle,
        Brightness.dark,
        glassStrength: GlassStrength.defaultStrength,
        accent: AppAccent.defaultAccent,
        pureBlack: ThemeSettingsProvider.defaultPureBlack,
      ),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: StartupFailurePanel(
                title: '核心初始化失敗',
                message: '核心服務沒有完成初始化，請重試或查看錯誤詳情。',
                details: details,
                onRetry: () => unawaited(_retryCriticalStartup()),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _runPostFirstFrameStartupTasks() async {
  if (kDebugMode) {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('recordLog', true);
    AppLog.i('Debug Mode: recordLog forced to TRUE');
  }
}

/// 開 App 的進場播完才做的清理，不和進場搶主執行緒（ADR 0018）。
void _runPostLaunchTasks() {
  unawaited(_cleanupLegacyCustomFontArtifacts());
  unawaited(_pruneStoredBooks());
  unawaited(PunctuationInk.onLaunchSettled());
  // 進搜尋頁的第一幀就畫得出搜尋紀錄。
  unawaited(SearchProvider.prefetchHistory());
}

/// 用上次存下的手機瀏覽器標識，之後讀到新的就存起來（[WebViewUserAgent]）。
/// 開 App 時不讀新的：讀一次要載入整個瀏覽器元件。
void _restoreWebViewUserAgent(SharedPreferences prefs) {
  WebViewUserAgent.value = prefs.getString(PreferKey.webViewUserAgent);
  WebViewUserAgent.onStore = (userAgent) =>
      unawaited(prefs.setString(PreferKey.webViewUserAgent, userAgent));
}

/// 刪掉書架以外的書留下的資料（剛開 App，還沒有詳情或閱讀器開著），再刪
/// 資料庫裡已經沒有的書、以及其他 App 版本留下的閱讀排版快取。
Future<void> _pruneStoredBooks() async {
  try {
    await BookStorageService().discardUnshelvedBooks();
  } catch (e, stack) {
    AppLog.e('Discard unshelved books failed: $e', error: e, stackTrace: stack);
  }
  try {
    final books = await getIt<BookDao>().getAll();
    await ReaderLayoutCache.retainOnly(
      bookUrls: books.map((book) => book.bookUrl),
      build: await ReaderLayoutCache.currentBuild(),
    );
  } catch (e, stack) {
    AppLog.e(
      'Prune reader layout caches failed: $e',
      error: e,
      stackTrace: stack,
    );
  }
}

Future<void> _cleanupLegacyCustomFontArtifacts() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey('selected_font_family')) {
      await prefs.remove('selected_font_family');
    }
  } catch (e, stack) {
    AppLog.e(
      'Cleanup legacy font pref failed: $e',
      error: e,
      stackTrace: stack,
    );
  }
  try {
    final documents = await AppStoragePaths.documentsDir();
    final fontsDir = Directory(p.join(documents.path, 'fonts'));
    if (await fontsDir.exists()) {
      await fontsDir.delete(recursive: true);
    }
  } catch (e, stack) {
    AppLog.e(
      'Cleanup legacy fonts directory failed: $e',
      error: e,
      stackTrace: stack,
    );
  }
}

class ReaderApp extends StatelessWidget {
  const ReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 一般設定只有深淺與語言影響 App 根部；更新與替換規則等通知不必重建
    // 整個 MaterialApp。外觀的每一項都用在主題，仍整體監聽（ADR 0029）。
    final (themeMode, locale) = context
        .select<SettingsProvider, (ThemeMode, Locale?)>(
          (settings) => (settings.themeMode, settings.locale),
        );
    return Consumer<ThemeSettingsProvider>(
      builder: (context, themeSettings, child) {
        return MaterialApp(
          title: kAppDisplayName,
          navigatorKey: rootNavigatorKey,
          scaffoldMessengerKey: scaffoldMessengerKey,
          navigatorObservers: [appRouteObserver, statusBarPolicy],
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(
            themeSettings.lightStyle,
            Brightness.light,
            glassStrength: themeSettings.glassStrength,
            accent: themeSettings.accent,
            pageTransition: themeSettings.pageTransition,
            fontFamily: themeSettings.uiFontFamily,
          ),
          darkTheme: buildAppTheme(
            themeSettings.darkStyle,
            Brightness.dark,
            glassStrength: themeSettings.glassStrength,
            accent: themeSettings.accent,
            pageTransition: themeSettings.pageTransition,
            pureBlack: themeSettings.pureBlack,
            fontFamily: themeSettings.uiFontFamily,
          ),
          themeMode: themeMode,
          // 使用者切換深淺或風格時由 ThemeRevealScope 從觸發點暈開新配色，
          // 底下的主題要一次到位；預設 200ms 的漸變會讓暈開的圓裡先露出
          // 半新半舊的顏色。系統自己切換深淺時也直接換。
          themeAnimationStyle: AnimationStyle.noAnimation,
          locale: locale,
          // 玻璃元件以 BackdropFilter.grouped 共用這裡的背景取樣。
          builder: (context, child) => TabletTextScale(
            child: TransitionOriginRecorder(
              child: ThemeRevealScope(
                child: StatusBarStableInset(
                  child: BackdropGroup(
                    child: ChineseDisplayScope(
                      child: HiddenWebViews(
                        child: child ?? const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          home: const _AssociationLifecycleHost(
            child: MainPage(onLaunchSettled: _runPostLaunchTasks),
          ),
        );
      },
    );
  }
}

class _AssociationLifecycleHost extends StatefulWidget {
  const _AssociationLifecycleHost({required this.child});

  final Widget child;

  @override
  State<_AssociationLifecycleHost> createState() =>
      _AssociationLifecycleHostState();
}

class _AssociationLifecycleHostState extends State<_AssociationLifecycleHost> {
  final AssociationHandlerService _associationHandler =
      AssociationHandlerService();
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _associationHandler.init(context);
    });
  }

  @override
  void dispose() {
    _associationHandler.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
