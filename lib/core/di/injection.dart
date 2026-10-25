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
import '../database/dao/cache_dao.dart';
import '../database/dao/cookie_dao.dart';
import '../database/dao/download_dao.dart';
import '../database/dao/read_record_dao.dart';
import '../database/dao/replace_rule_dao.dart';
import '../database/dao/search_book_dao.dart';
import '../database/dao/search_history_dao.dart';
import '../database/dao/search_keyword_dao.dart';
import '../database/dao/keyboard_assist_dao.dart';
import '../database/dao/server_dao.dart';
import '../database/dao/reader_chapter_content_dao.dart';
import '../services/tts_service.dart';
import '../services/check_source_service.dart';
import '../services/app_version.dart';
import '../services/crash_handler.dart';
import '../engine/source_isolate/source_isolate.dart';

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

  // 2. 核心資料庫與 DAO
  registerDatabase(AppDatabase());

  // 3. 其它核心服務註冊
  getIt.registerSingleton<NetworkService>(NetworkService());
  getIt.registerSingleton<TTSService>(TTSService());
  getIt.registerLazySingleton<CheckSourceService>(CheckSourceService.new);

  // 預先載入 SharedPreferences，讓 SettingsProvider / BookshelfProvider 建構時同步讀取，消除第一幀閃爍
  final prefs = await SharedPreferences.getInstance();
  getIt.registerSingleton<SharedPreferences>(prefs);

  // 4. 初始化啟動所需服務。
  await Future.wait([
    CrashHandler.init(),
    getIt<NetworkService>().init(),
    AppVersion.current(),
  ]);

  // 書源的抓取與解析改在書源 isolate（只有 App 的主 isolate 會開，見
  // [SourceIsolate.enabled]）；不等它開好，第一個書源工作才會等。
  SourceIsolate.start();

  // 朗讀引擎現在就開始開，和讀書架、載字典同時進行；開 App 的進場在底色
  // 時等它開好（[TTSService.ready]）。
  unawaited(getIt<TTSService>().init());
}

/// 註冊資料庫與所有 DAO。主 isolate 與書源 isolate（連到同一個資料庫）共用。
void registerDatabase(AppDatabase database) {
  getIt.registerSingleton<AppDatabase>(database);
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
}
