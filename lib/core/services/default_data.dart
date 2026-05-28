import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synchronized/synchronized.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/search_history_dao.dart';
import 'package:night_reader/core/database/dao/cache_dao.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'chinese_utils.dart';
import 'package:night_reader/shared/theme/app_theme.dart';
import 'package:night_reader/core/di/injection.dart';

/// DefaultData - 預設資料初始化
/// (原 Android help/DefaultData.kt)
class DefaultData {
  DefaultData._();
  static final _initLock = Lock();
  static bool _essentialInitialized = false;
  static bool _deferredInitialized = false;

  static Future<void> init() async {
    await _initLock.synchronized(() async {
      await _initEssential();
      await _initDeferred();
    });
  }

  static Future<void> initEssential() async {
    await _initLock.synchronized(_initEssential);
  }

  static Future<void> initDeferred() async {
    await _initLock.synchronized(_initDeferred);
  }

  static Future<void> _initEssential() async {
    if (_essentialInitialized) return;
    await AppTheme.init();
    _essentialInitialized = true;
  }

  static Future<void> _initDeferred() async {
    if (_deferredInitialized) return;
    await _initEssential();

    final prefs = await SharedPreferences.getInstance();
    // 原 Android versionCode 判斷
    const currentDataVersion = 101;
    final savedDataVersion = prefs.getInt('default_data_version') ?? 0;

    if (savedDataVersion < currentDataVersion) {
      await _loadDefaultSources();
      await prefs.setInt('default_data_version', currentDataVersion);
    }

    // 2. 啟動時維護與清理 (原 Android App.onCreate 中的各式 Clear 與 adjustSortNumber)
    await _maintenance();

    // 3. 預熱與同步 (原 Android ChineseUtils.preLoad 與 AppWebDav 同步)
    _startBackgroundTasks();
    _deferredInitialized = true;
  }

  static Future<void> _maintenance() async {
    try {
      // 校正書源排序 (原 Android SourceHelp.adjustSortNumber)
      await getIt<BookSourceDao>().adjustSortNumbers();

      // 維護與清理
      final now = DateTime.now().millisecondsSinceEpoch;

      // 清理超過 7 天的搜尋歷史 (對標 Android SearchKeywordDao.deleteOld)
      final sevenDaysAgo = now - 7 * 24 * 60 * 60 * 1000;
      await getIt<SearchHistoryDao>().clearOld(sevenDaysAgo);

      // 清理過期快取 (對標 Android CacheDao.clearDeadline)
      await getIt<CacheDao>().clearDeadline(now);
    } catch (e) {
      AppLog.e('Maintenance error: $e', error: e);
    }
  }

  static void _startBackgroundTasks() {
    // A. 預熱簡繁轉換 (原 Android ChineseUtils.preLoad)
    unawaited(_warmChineseUtils());
  }

  static Future<void> _warmChineseUtils() async {
    try {
      await ChineseUtils.initialize();
      ChineseUtils.s2t('');
    } catch (e) {
      AppLog.e('ChineseUtils warmup error: $e', error: e);
    }
  }

  /// 載入預設書源。
  ///
  /// `assets/default_sources/sources.json` 目前刻意保留為空陣列占位檔，
  /// 代表 App 不內建預設書源，但仍保留統一的初始化入口。
  static Future<void> _loadDefaultSources() async {
    try {
      final jsonStr = await rootBundle.loadString(
        'assets/default_sources/sources.json',
      );
      final List<dynamic> jsonList = jsonDecode(jsonStr);
      final sources =
          jsonList.map((j) => BookSource.fromJson(jsonAt(j))).toList();
      await getIt<BookSourceDao>().insertOrUpdateAll(sources);
    } catch (e) {
      AppLog.e('Error loading default sources: $e', error: e);
    }
  }

  static Map<String, dynamic> jsonAt(dynamic j) => Map<String, dynamic>.from(j);
}
