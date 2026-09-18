import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/network_service.dart';
import '../database/app_database.dart';
import '../database/dao/book_dao.dart';
import '../database/dao/book_source_dao.dart';
import '../database/dao/chapter_dao.dart';
import '../database/dao/book_group_dao.dart';
import '../database/dao/bookmark_dao.dart';
import '../database/dao/cache_dao.dart';
import '../database/dao/cookie_dao.dart';
import '../database/dao/download_dao.dart';
import '../database/dao/read_record_dao.dart';
import '../database/dao/replace_rule_dao.dart';
import '../database/dao/rule_sub_dao.dart';
import '../database/dao/search_book_dao.dart';
import '../database/dao/search_history_dao.dart';
import '../database/dao/search_keyword_dao.dart';
import '../database/dao/keyboard_assist_dao.dart';
import '../database/dao/server_dao.dart';
import '../database/dao/reader_chapter_content_dao.dart';
import '../services/tts_service.dart';
import '../services/crash_handler.dart';
import '../services/app_log_service.dart';

final getIt = GetIt.instance;

/// Dependency Injection Setup
/// 註冊所有全域服務與單例
Future<void> configureDependencies() async {
  // 1. 日誌服務 (優先註冊)
  getIt.registerSingleton<Logger>(
    Logger(
      printer: PrettyPrinter(
        methodCount: 0, // 設為 0 以隱藏日誌產生的原始碼行號資訊 (#0, #1)
        errorMethodCount: 5,
        lineLength: 80,
        colors: true,
        printEmojis: true,
        dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
        noBoxingByDefault: true, // 預設不畫框框，讓日誌更緊湊
      ),
    ),
  );

  // 2. 核心資料庫服務 (切換為 SQLite)
  final appDatabase = AppDatabase();
  getIt.registerSingleton<AppDatabase>(appDatabase);

  // 3. DAO 註冊 (統一使用 SQLite 實作)
  getIt.registerLazySingleton<BookDao>(() => BookDao(getIt<AppDatabase>()));
  getIt.registerLazySingleton<BookSourceDao>(
    () => BookSourceDao(getIt<AppDatabase>()),
  );
  getIt.registerLazySingleton<ChapterDao>(
    () => ChapterDao(getIt<AppDatabase>()),
  );
  getIt.registerLazySingleton<BookGroupDao>(
    () => BookGroupDao(getIt<AppDatabase>()),
  );
  getIt.registerLazySingleton<BookmarkDao>(
    () => BookmarkDao(getIt<AppDatabase>()),
  );
  getIt.registerLazySingleton<CacheDao>(() => CacheDao(getIt<AppDatabase>()));
  getIt.registerLazySingleton<CookieDao>(() => CookieDao(getIt<AppDatabase>()));
  getIt.registerLazySingleton<DownloadDao>(
    () => DownloadDao(getIt<AppDatabase>()),
  );
  getIt.registerLazySingleton<ReadRecordDao>(
    () => ReadRecordDao(getIt<AppDatabase>()),
  );
  getIt.registerLazySingleton<ReplaceRuleDao>(
    () => ReplaceRuleDao(getIt<AppDatabase>()),
  );
  getIt.registerLazySingleton<RuleSubDao>(
    () => RuleSubDao(getIt<AppDatabase>()),
  );
  getIt.registerLazySingleton<SearchBookDao>(
    () => SearchBookDao(getIt<AppDatabase>()),
  );
  getIt.registerLazySingleton<SearchHistoryDao>(
    () => SearchHistoryDao(getIt<AppDatabase>()),
  );
  getIt.registerLazySingleton<SearchKeywordDao>(
    () => SearchKeywordDao(getIt<AppDatabase>()),
  );
  getIt.registerLazySingleton<KeyboardAssistDao>(
    () => KeyboardAssistDao(getIt<AppDatabase>()),
  );
  getIt.registerLazySingleton<ServerDao>(() => ServerDao(getIt<AppDatabase>()));
  getIt.registerLazySingleton<ReaderChapterContentDao>(
    () => ReaderChapterContentDao(getIt<AppDatabase>()),
  );

  // 4. 其它核心服務註冊
  getIt.registerSingleton<NetworkService>(NetworkService());
  getIt.registerSingleton<TTSService>(TTSService());

  // 預先載入 SharedPreferences，讓 SettingsProvider / BookshelfProvider 建構時同步讀取，消除第一幀閃爍
  final prefs = await SharedPreferences.getInstance();
  getIt.registerSingleton<SharedPreferences>(prefs);

  // 5. 初始化啟動所需服務。
  // TTS / AudioService 是可選能力，某些 Android ROM 可能讓 platform
  // channel 初始化延遲或失敗；不可讓它阻塞 runApp 與原生 Splash。
  await Future.wait([CrashHandler.init(), getIt<NetworkService>().init()]);

  unawaited(_initializeTtsInBackground(getIt<TTSService>()));
}

Future<void> _initializeTtsInBackground(TTSService service) async {
  try {
    await service.init();
  } catch (error, stackTrace) {
    // TTS 不可用時仍應保留書架與閱讀功能。
    AppLog.e(
      'TTS background initialization failed; continuing without TTS: $error',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
