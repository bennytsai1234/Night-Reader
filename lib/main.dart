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

import 'core/services/chinese_display.dart';
import 'core/di/injection.dart';
import 'core/database/dao/book_dao.dart';
import 'core/storage/app_storage_paths.dart';
import 'app_providers.dart';
import 'shared/theme/app_tokens.dart';
import 'shared/theme/custom_app_theme.dart';
import 'shared/navigation/app_route_observer.dart';
import 'shared/navigation/status_bar.dart';
import 'features/association/association_handler_service.dart';
import 'features/settings/settings_provider.dart';
import 'features/settings/theme_settings_provider.dart';
import 'features/welcome/main_page.dart';
import 'features/welcome/startup_failure_panel.dart';
import 'core/services/app_log_service.dart';
import 'core/services/crash_handler.dart';
import 'core/startup/startup_retry_gate.dart';

import 'package:flutter_native_splash/flutter_native_splash.dart';

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
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
const String kAppDisplayName = '夜讀';
final StartupRetryGate _startupRetryGate = StartupRetryGate();

/// 內建標點字型 NightReaderPunct 的 SIL OFL 授權，列在「開源授權」頁。
Stream<LicenseEntry> _punctFontLicense() async* {
  yield LicenseEntryWithLineBreaks(const <String>[
    'NightReaderPunct (Noto Sans CJK TC)',
  ], await rootBundle.loadString('assets/fonts/OFL.txt'));
}

void main() {
  runZonedGuarded(_startApp, (error, stack) {
    AppLog.e('Uncaught Error: $error', error: error, stackTrace: stack);
    CrashHandler.recordError(error, stack);
  });
}

Future<void> _startApp() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  GestureBinding.instance.resamplingEnabled = true;
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  AppLog.i('WidgetsFlutterBinding Initialized');
  LicenseRegistry.addLicense(_punctFontLicense);

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
      // Ensure a Flutter build/provider failure cannot leave the native splash
      // covering the ErrorWidget returned above.
      FlutterNativeSplash.remove();
      FlutterError.presentError(details);
      AppLog.e(
        'Flutter Error: ${details.exception}',
        error: details.exception,
        stackTrace: details.stack,
      );
      CrashHandler.recordFlutterError(details);
    };

    AppLog.i('$kAppDisplayName Ready to Run');

    runApp(
      MultiProvider(
        providers: AppProviders.providers,
        child: const ReaderApp(),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_runPostFirstFrameStartupTasks());
    });
  } catch (e, stack) {
    AppLog.e('Startup Critical Error: $e', error: e, stackTrace: stack);
    CrashHandler.recordError(e, stack);
    // configureDependencies 失敗時 MainPage 不會建立，不能依賴它釋放原生
    // Splash；否則錯誤頁會被永久蓋住，看起來像 App 卡在開啟畫面。
    FlutterNativeSplash.remove();
    runApp(_StartupFailureApp(error: e, stackTrace: stack));
  }
}

Widget buildFlutterErrorWidget(
  FlutterErrorDetails details, {
  VoidCallback? releaseNativeSplash,
}) {
  // A provider/widget build failure can happen after runApp(), so the
  // dependency try/catch cannot release the native splash for this path.
  (releaseNativeSplash ?? FlutterNativeSplash.remove)();
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
    return MaterialApp(
      title: kAppDisplayName,
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.black,
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

  unawaited(_cleanupLegacyCustomFontArtifacts());
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
    return Consumer2<SettingsProvider, ThemeSettingsProvider>(
      builder: (context, settings, themeSettings, child) {
        return MaterialApp(
          title: kAppDisplayName,
          navigatorKey: rootNavigatorKey,
          scaffoldMessengerKey: scaffoldMessengerKey,
          navigatorObservers: [appRouteObserver, statusBarPolicy],
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(
            themeSettings.style,
            Brightness.light,
            glassStrength: themeSettings.glassStrength,
          ),
          darkTheme: buildAppTheme(
            themeSettings.style,
            Brightness.dark,
            glassStrength: themeSettings.glassStrength,
          ),
          themeMode: settings.themeMode,
          locale: settings.locale,
          // 玻璃元件以 BackdropFilter.grouped 共用這裡的背景取樣。
          builder: (context, child) => StatusBarStableInset(
            child: BackdropGroup(
              child: ChineseDisplayScope(
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          ),
          home: const _AssociationLifecycleHost(child: MainPage()),
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
