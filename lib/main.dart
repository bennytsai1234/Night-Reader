import 'dart:async';
import 'dart:io';
import 'package:flutter/gestures.dart';
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
import 'shared/theme/custom_app_theme.dart';
import 'shared/navigation/app_route_observer.dart';
import 'features/association/association_handler_service.dart';
import 'features/settings/settings_provider.dart';
import 'features/settings/theme_settings_provider.dart';
import 'features/welcome/main_page.dart';
import 'features/welcome/startup_failure_panel.dart';
import 'core/services/app_log_service.dart';
import 'core/services/crash_handler.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await configureDependencies();
      final bookDao = getIt<BookDao>();
      final books = await bookDao.getInBookshelf();
      getIt<Logger>().i(
        'Background Task: Checking updates for ${books.length} books',
      );
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
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  GestureBinding.instance.resamplingEnabled = true;
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  AppLog.i('WidgetsFlutterBinding Initialized');

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
    await Workmanager().initialize(callbackDispatcher);
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
          navigatorObservers: [appRouteObserver],
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(
            themeSettings.effectiveAppLight,
            Brightness.light,
          ),
          darkTheme: buildAppTheme(
            themeSettings.effectiveAppDark,
            Brightness.dark,
          ),
          themeMode: settings.themeMode,
          locale: settings.locale,
          builder: (context, child) => child ?? const SizedBox.shrink(),
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
