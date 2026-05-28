import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

import 'core/di/injection.dart';
import 'core/database/dao/book_dao.dart';
import 'core/storage/app_storage_paths.dart';
import 'app_providers.dart';
import 'shared/theme/app_theme.dart';
import 'features/settings/settings_provider.dart';
import 'features/welcome/splash_page.dart';
import 'features/welcome/startup_failure_panel.dart';
import 'core/services/app_log_service.dart';
import 'core/services/crash_handler.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      // 這裡需要重新初始化必要的 DI 服務 (因為後台 Isolate 不共享主執行緒狀態)
      await configureDependencies();

      final bookDao = getIt<BookDao>();
      final books = await bookDao.getInBookshelf();

      getIt<Logger>().i(
        'Background Task: Checking updates for ${books.length} books',
      );
      // 這裡可以進一步調用 CheckSourceService 執行真實更新

      return Future.value(true);
    } catch (e) {
      return Future.value(false);
    }
  });
}

final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
const String kAppDisplayName = '夜讀';

void main() {
  runZonedGuarded(_startApp, (error, stack) {
    AppLog.e('Uncaught Error: $error', error: error, stackTrace: stack);
    CrashHandler.recordError(error, stack);
  });
}

Future<void> _startApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppLog.i('WidgetsFlutterBinding Initialized');

  // 自定義錯誤畫面，避免黑屏
  ErrorWidget.builder = (FlutterErrorDetails details) {
    AppLog.e(
      'Rendering Error: ${details.exception}',
      error: details.exception,
      stackTrace: details.stack,
    );
    CrashHandler.recordFlutterError(details);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Container(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Detected an Error:',
                style: TextStyle(
                  color: Colors.red,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                details.exceptionAsString(),
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              const SizedBox(height: 10),
              Text(
                details.stack.toString(),
                style: const TextStyle(color: Colors.grey, fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    );
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
    runApp(_StartupFailureApp(error: e, stackTrace: stack));
  }
}

Future<void> _retryCriticalStartup() async {
  try {
    await getIt.reset();
  } catch (e, stack) {
    AppLog.e('Dependency reset failed: $e', error: e, stackTrace: stack);
  }
  await _startApp();
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

  try {
    AppLog.i('Initializing Workmanager...');
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: kDebugMode,
    );
  } catch (e, stack) {
    AppLog.e('Workmanager init failed: $e', error: e, stackTrace: stack);
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

class ReaderApp extends StatefulWidget {
  const ReaderApp({super.key});

  @override
  State<ReaderApp> createState() => _ReaderAppState();
}

class _ReaderAppState extends State<ReaderApp> {
  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, settings, child) {
        return MaterialApp(
          title: kAppDisplayName,
          navigatorKey: rootNavigatorKey,
          scaffoldMessengerKey: scaffoldMessengerKey,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: settings.themeMode,
          locale: settings.locale,
          builder: (context, child) => child ?? const SizedBox.shrink(),
          home: const SplashPage(),
        );
      },
    );
  }
}
