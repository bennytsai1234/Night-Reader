import 'dart:io' hide Cookie;
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'tables/app_tables.dart';
// model imports required by app_database.g.dart (part shares this namespace)
import '../models/book.dart';
import '../models/chapter.dart';
import '../models/bookmark.dart';
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
import '../models/rule_sub.dart';
import '../models/source_subscription.dart';
import '../models/search_book.dart';
import '../models/download_task.dart';
import '../models/search_keyword.dart';
import 'dao/book_dao.dart';
import 'dao/chapter_dao.dart';
import 'dao/book_source_dao.dart';
import 'dao/book_group_dao.dart';
import 'dao/bookmark_dao.dart';
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
import 'dao/rule_sub_dao.dart';
import 'dao/source_subscription_dao.dart';
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
    Bookmarks,
    Cookies,
    DictRules,
    HttpTtsTable,
    ReadRecords,
    Servers,
    TxtTocRules,
    CacheTable,
    KeyboardAssists,
    RuleSubs,
    SourceSubscriptions,
    SearchBooks,
    DownloadTasks,
    SearchKeywords,
  ],
  daos: [
    BookDao,
    ChapterDao,
    BookSourceDao,
    BookGroupDao,
    BookmarkDao,
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
    RuleSubDao,
    SourceSubscriptionDao,
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
  AppDatabase.forTesting(QueryExecutor executor) : super(executor);

  @override
  int get schemaVersion => 2;

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
    },
    beforeOpen: (_) async {
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
    CREATE INDEX IF NOT EXISTS idx_bookmarks_book
    ON bookmarks (bookUrl)
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
    CREATE INDEX IF NOT EXISTS idx_rule_subs_order
    ON rule_subs ("order")
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_source_subscriptions_order
    ON source_subscriptions ("order")
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

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
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
    return NativeDatabase.createInBackground(file);
  });
}
