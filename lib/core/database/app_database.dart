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
import '../models/bookmark.dart';
import '../models/highlight.dart';
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
import 'dao/bookmark_dao.dart';
import 'dao/highlight_dao.dart';
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
    Bookmarks,
    Highlights,
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
    BookmarkDao,
    HighlightDao,
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
  int get schemaVersion => 15;

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
        // 舊的書籤表（照書的網址記）與索引刪掉；現在的書籤表在 schema 10
        // 重新建立。
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
        // 開跑時照樣跳過。表照現在的樣子重建，schema 14 的失敗欄位也在這裡
        // 建好、留空。
        await m.alterTable(
          TableMigration(
            downloadTasks,
            newColumns: [
              downloadTasks.startChapterUrl,
              downloadTasks.endChapterUrl,
              downloadTasks.lastErrorReason,
              downloadTasks.lastErrorMessage,
              downloadTasks.lastErrorChapterIndex,
            ],
          ),
        );
      } else if (from < 14) {
        // 下載失敗的類型、訊息與章節存進資料庫，重開 App 後「查看失敗原因」
        // 照樣看得到；升級前失敗的任務沒有記錄，留空。
        await m.addColumn(downloadTasks, downloadTasks.lastErrorReason);
        await m.addColumn(downloadTasks, downloadTasks.lastErrorMessage);
        await m.addColumn(downloadTasks, downloadTasks.lastErrorChapterIndex);
      }
      if (from < 7) {
        // 閱讀統計的「今天／本週」改記每天的秒數；之前只有累計，
        // 所以這兩個數字從升級後開始算。
        await m.createTable(readDays);
      }
      if (from < 8) {
        // 章節的身分從章節網址改成書＋章節網址：不同書的同名分卷補出同一個
        // 網址時，後存的那本會搶走前一本的那一章。舊表網址本來就不重複，
        // 照原樣搬過去；重建表會丟掉章節的索引，重新建立。
        await m.alterTable(TableMigration(chapters));
        await customStatement(_chaptersIndexStatement);
      }
      if (from < 9) {
        // 多台手機同步比進度新舊用的「位置最後移動的時間」（ADR 0039）。
        // 最近閱讀時間開書沒翻頁也會更新，只能當升級時的估計。
        await m.addColumn(books, books.progressTime);
        await customStatement('UPDATE books SET progressTime = durChapterTime');
      }
      if (from < 10) {
        // 書籤：照書名加作者記，跟著書走、不跟書源。
        await m.createTable(bookmarks);
      }
      if (from < 11) {
        // 標註：同書籤，照書名加作者記（ADR 0044）。
        await m.createTable(highlights);
      } else if (from < 12) {
        // 標註的備忘；schema 11 以前的在上面照現在的樣子建表，已經有這欄。
        await m.addColumn(highlights, highlights.note);
      }
      if (from < 13) {
        // 本地書原檔的指紋（ADR 0039）。要讀整個檔才算得出來，升級時先留空，
        // 由背景 isolate 補算（`fillLocalBookFingerprints`）。
        await m.addColumn(books, books.fileFingerprint);
      }
      if (from < 15) {
        await _classifyExistingSources();
      }
    },
    beforeOpen: (_) async {
      if (_separateConnection) return;
      await customStatement('PRAGMA optimize');
    },
  );

  /// 書源分成小說、漫畫、有聲（ADR 0051）：類型寫 0 但名稱帶漫畫、有聲字樣
  /// 的補寫類型；舊版停用並標成「非小說源」的漫畫、有聲書源拿掉標記、重新
  /// 啟用。影視、文件書源照舊。
  Future<void> _classifyExistingSources() async {
    // 只建了部分舊表的測試資料庫沒有書源表。
    final hasTable = await customSelect(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' "
      "AND name = 'book_sources'",
    ).get();
    if (hasTable.isEmpty) return;
    final rows = await customSelect(
      'SELECT bookSourceUrl, bookSourceName, bookSourceType, bookSourceGroup, '
      'bookSourceComment, enabled, enabledExplore, searchUrl FROM book_sources',
    ).get();
    final kinds = <String, BookSourceKind>{};
    for (final row in rows) {
      final source = BookSource(
        bookSourceUrl: row.read<String>('bookSourceUrl'),
        bookSourceName: row.read<String>('bookSourceName'),
        bookSourceType: row.read<int>('bookSourceType'),
        bookSourceGroup: row.read<String?>('bookSourceGroup'),
        bookSourceComment: row.read<String?>('bookSourceComment'),
        enabled: row.read<bool>('enabled'),
        enabledExplore: row.read<bool>('enabledExplore'),
        searchUrl: row.read<String?>('searchUrl'),
      );
      final before = (
        source.bookSourceType,
        source.bookSourceGroup,
        source.enabled,
        source.enabledExplore,
      );
      source.prepareIncoming();
      if (source.sourceKind != BookSourceKind.unsupported) {
        kinds[source.bookSourceUrl] = source.sourceKind;
      }
      final after = (
        source.bookSourceType,
        source.bookSourceGroup,
        source.enabled,
        source.enabledExplore,
      );
      if (before == after) continue;
      await customStatement(
        'UPDATE book_sources SET bookSourceType = ?, bookSourceGroup = ?, '
        'enabled = ?, enabledExplore = ? WHERE bookSourceUrl = ?',
        [
          source.bookSourceType,
          source.bookSourceGroup,
          source.enabled ? 1 : 0,
          source.enabledExplore ? 1 : 0,
          source.bookSourceUrl,
        ],
      );
    }
    // 用這些書源加的書跟著換類別，同存書源時（ADR 0053）。每個書源都比，
    // 不只這次改了類型的：重跑也補得到上次漏的。
    await BookDao(this).followSourceKinds(kinds);
  }

  Future<void> _createPerformanceIndexes() async {
    for (final statement in _performanceIndexStatements) {
      await customStatement(statement);
    }
  }

  static const String _chaptersIndexStatement = '''
    CREATE INDEX IF NOT EXISTS idx_chapters_book_index
    ON chapters (bookUrl, "index")
    ''';

  static const List<String> _performanceIndexStatements = [
    '''
    CREATE INDEX IF NOT EXISTS idx_books_bookshelf_recent
    ON books (isInBookshelf, durChapterTime DESC)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_books_bookshelf_group
    ON books (isInBookshelf, "group")
    ''',
    _chaptersIndexStatement,
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
