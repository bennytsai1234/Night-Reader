import 'dart:async';
import 'dart:io' hide Cookie;

import 'package:drift/drift.dart';
import 'package:drift/isolate.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables/app_tables.dart';
// model imports required by app_database.g.dart (part shares this namespace)
import '../models/book.dart';
import '../models/chapter.dart';
import '../models/replace_rule.dart';
import '../models/book_source.dart';
import '../models/book_group.dart';
import '../models/cookie.dart';
import '../models/dict_rule.dart';
import '../models/http_tts.dart';
import '../models/read_record.dart';
import '../models/server.dart';
import '../models/txt_toc_rule.dart';
import '../models/cache.dart';
import '../models/keyboard_assist.dart';
import '../models/search_book.dart';
import '../models/download_task.dart';
import '../models/search_keyword.dart';
import 'dao/book_dao.dart';
import 'dao/chapter_dao.dart';
import 'dao/book_source_dao.dart';
import 'dao/book_group_dao.dart';
import 'dao/replace_rule_dao.dart';
import 'dao/search_history_dao.dart';
import 'dao/cookie_dao.dart';
import 'dao/dict_rule_dao.dart';
import 'dao/http_tts_dao.dart';
import 'dao/read_record_dao.dart';
import 'dao/server_dao.dart';
import 'dao/txt_toc_rule_dao.dart';
import 'dao/cache_dao.dart';
import 'dao/keyboard_assist_dao.dart';
import 'dao/search_book_dao.dart';
import 'dao/download_dao.dart';
import 'dao/search_keyword_dao.dart';
import 'dao/reader_chapter_content_dao.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Books,
    Chapters,
    ReaderChapterContents,
    BookSources,
    BookGroups,
    SearchHistoryTable,
    ReplaceRules,
    Cookies,
    DictRules,
    HttpTtsTable,
    ReadRecords,
    ReadDays,
    Servers,
    TxtTocRules,
    CacheTable,
    KeyboardAssists,
    SearchBooks,
    DownloadTasks,
    SearchKeywords,
  ],
  daos: [
    BookDao,
    ChapterDao,
    BookSourceDao,
    BookGroupDao,
    ReplaceRuleDao,
    SearchHistoryDao,
    CookieDao,
    DictRuleDao,
    HttpTtsDao,
    ReadRecordDao,
    ServerDao,
    TxtTocRuleDao,
    CacheDao,
    KeyboardAssistDao,
    SearchBookDao,
    DownloadDao,
    SearchKeywordDao,
    ReaderChapterContentDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  static final AppDatabase _instance = AppDatabase._internal();
  factory AppDatabase() => _instance;
  AppDatabase._internal() : super(_openConnection());

  /// 連上另一個 isolate 開好的資料庫（[sharedIsolate]）：書源 isolate 用它，
  /// 和主 isolate 共用同一個連線，寫入會更新兩邊的 `watch()`。
  AppDatabase.connected(DatabaseConnection super.connection);
  AppDatabase.forTesting(super.executor);

  /// 不經過 drift isolate、直接連到 [path] 的另一條連線。只給網路 isolate
  /// 用（`SourceIo`）：drift isolate 有交易進行時其他查詢都要排隊，它替停住
  /// 的書源 isolate 讀資料庫時不能排在那段交易後面。這條連線的寫入不會更新
  /// 別人的 `watch()`。
  AppDatabase.separateConnection(String path)
    : _separateConnection = true,
      super(DatabaseConnection(_openFile(path)));

  /// [AppDatabase.separateConnection]：打開時不做要寫入的整理
  /// （`PRAGMA optimize`），停住的書源 isolate 手上有交易時那會等到逾時。
  bool _separateConnection = false;

  /// 執行查詢的 drift isolate。主 isolate 與書源 isolate 都連到它；兩邊各自
  /// 開連線的話，一邊的寫入不會更新另一邊的 `watch()`（drift 文件 Isolates）。
  static Future<DriftIsolate> get sharedIsolate => _sharedIsolate.future;
  static final Completer<DriftIsolate> _sharedIsolate =
      Completer<DriftIsolate>()
        // 開不起來時錯誤由查詢那一端回報；沒有人等這個 isolate 時不另外報錯。
        ..future.ignore();

  /// [sharedIsolate] 開的資料庫檔案。
  static Future<String?> get sharedFile => _sharedFile.future;
  static final Completer<String?> _sharedFile = Completer<String?>();

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _createPerformanceIndexes();
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await _createPerformanceIndexes();
      }
      if (from < 3) {
        // 書籤功能已移除；表與索引一併刪除，不留無人使用的資料。
        await customStatement('DROP INDEX IF EXISTS idx_bookmarks_book');
        await customStatement('DROP TABLE IF EXISTS bookmarks');
      }
      if (from < 4) {
        // 下載佇列的順序改存資料庫；既有任務照加入的先後（rowid）排。
        await m.addColumn(downloadTasks, downloadTasks.sortOrder);
        await customStatement('UPDATE download_tasks SET sortOrder = rowid');
      }
      if (from < 5) {
        // 書源訂閱功能已移除；rule_subs 與更早移除時沒清掉的
        // source_subscriptions 一併刪除，不留無人使用的表。
        await customStatement('DROP INDEX IF EXISTS idx_rule_subs_order');
        await customStatement('DROP TABLE IF EXISTS rule_subs');
        await customStatement(
          'DROP INDEX IF EXISTS idx_source_subscriptions_order',
        );
        await customStatement('DROP TABLE IF EXISTS source_subscriptions');
      }
      if (from < 6) {
        // 下載任務的範圍從章節序號改記章節網址（ADR 0008）。既有任務兩端
        // 都留空，也就是整本：絕大多數本來就是書架自動下載，已下載的章節
        // 開跑時照樣跳過。
        await m.alterTable(
          TableMigration(
            downloadTasks,
            newColumns: [
              downloadTasks.startChapterUrl,
              downloadTasks.endChapterUrl,
            ],
          ),
        );
      }
      if (from < 7) {
        // 閱讀統計的「今天／本週」改記每天的秒數；之前只有累計，
        // 所以這兩個數字從升級後開始算。
        await m.createTable(readDays);
      }
    },
    beforeOpen: (_) async {
      if (_separateConnection) return;
      await customStatement('PRAGMA optimize');
    },
  );

  Future<void> _createPerformanceIndexes() async {
    for (final statement in _performanceIndexStatements) {
      await customStatement(statement);
    }
  }

  static const List<String> _performanceIndexStatements = [
    '''
    CREATE INDEX IF NOT EXISTS idx_books_bookshelf_recent
    ON books (isInBookshelf, durChapterTime DESC)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_books_bookshelf_group
    ON books (isInBookshelf, "group")
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_chapters_book_index
    ON chapters (bookUrl, "index")
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_reader_content_book_status_index
    ON reader_chapter_contents (origin, bookUrl, status, chapterIndex)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_reader_content_book_url
    ON reader_chapter_contents (bookUrl)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_reader_content_status
    ON reader_chapter_contents (status)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_book_sources_order
    ON book_sources (customOrder)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_book_sources_enabled_order
    ON book_sources (enabled, customOrder)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_book_groups_order
    ON book_groups ("order")
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_search_history_time
    ON search_history_table (searchTime DESC)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_replace_rules_enabled_order
    ON replace_rules (isEnabled, "order")
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_read_records_name
    ON read_records (bookName)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_read_records_last_read
    ON read_records (lastRead DESC)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_txt_toc_rules_enabled_serial
    ON txt_toc_rules (enable, serialNumber)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_cache_deadline
    ON cache_table (deadline)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_keyboard_assists_serial
    ON keyboard_assists (serialNo)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_search_books_name_author_order
    ON search_books (name, author, originOrder)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_search_books_origin
    ON search_books (origin)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_search_books_add_time
    ON search_books (addTime)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_download_tasks_update_time
    ON download_tasks (addTime)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_download_tasks_status
    ON download_tasks (status)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_search_keywords_usage
    ON search_keywords (usage DESC)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_search_keywords_last_use_time
    ON search_keywords (lastUseTime DESC)
    ''',
  ];

  static Future<String> getDatabasePath() async {
    final appSupportDir = await getApplicationSupportDirectory();
    return p.join(appSupportDir.path, 'databases', 'night_reader.db');
  }
}

/// 在背景的 drift isolate 執行查詢，並讓其他 isolate 能連上同一個
/// （[AppDatabase.sharedIsolate]）。多個 isolate 共用時 drift 建議用
/// `DatabaseConnection.delayed`，不用只共用執行器、不同步串流的
/// `LazyDatabase`。
DatabaseConnection _openConnection() {
  return DatabaseConnection.delayed(
    Future(() async {
      try {
        final path = await _databasePath();
        final isolate = await spawnDatabaseIsolate(path);
        AppDatabase._sharedIsolate.complete(isolate);
        AppDatabase._sharedFile.complete(path);
        return await isolate.connect();
      } catch (error, stackTrace) {
        AppDatabase._sharedIsolate.completeError(error, stackTrace);
        if (!AppDatabase._sharedFile.isCompleted) {
          AppDatabase._sharedFile.complete(null);
        }
        rethrow;
      }
    }),
  );
}

Future<String> _databasePath() async {
  final appSupportDir = await getApplicationSupportDirectory();
  final dbDir = Directory(p.join(appSupportDir.path, 'databases'));
  if (!dbDir.existsSync()) {
    dbDir.createSync(recursive: true);
  }
  final file = File(p.join(dbDir.path, 'night_reader.db'));
  // 從 inkpage_reader 品牌改名後的一次性遷移：舊裝置上 DB 仍叫 inkpage_reader.db
  if (!file.existsSync()) {
    final legacy = File(p.join(dbDir.path, 'inkpage_reader.db'));
    if (legacy.existsSync()) {
      legacy.renameSync(file.path);
    }
  }
  return file.path;
}

/// 開一個執行 [path] 查詢的 drift isolate（[AppDatabase.sharedIsolate]）。
/// 開資料庫的函式會送進新的 isolate，所以在這裡建立，只捕捉檔案路徑。
Future<DriftIsolate> spawnDatabaseIsolate(String path) =>
    DriftIsolate.spawn(() => _openFile(path));

/// 資料庫檔案用 WAL：drift isolate 與網路 isolate 各有一條連線
/// （[AppDatabase.separateConnection]），讀和寫可以同時進行，讀的一方不會
/// 讓另一條連線的交易提交失敗（ADR 0034）。兩條連線同時寫才要等，等的上限
/// 遠長於最長的寫入（換掉整本目錄）。
QueryExecutor _openFile(String path) => NativeDatabase(
  File(path),
  setup: (database) {
    database.execute('PRAGMA journal_mode = WAL');
    database.execute('PRAGMA busy_timeout = 5000');
  },
);
