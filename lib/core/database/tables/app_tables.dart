import 'dart:convert';
import 'package:drift/drift.dart';
import '../../models/book.dart';
import '../../models/chapter.dart';
import '../../models/bookmark.dart';
import '../../models/replace_rule.dart';
import '../../models/book_source.dart';
import '../../models/book_group.dart';
import '../../models/cookie.dart';
import '../../models/dict_rule.dart';
import '../../models/http_tts.dart';
import '../../models/read_record.dart';
import '../../models/server.dart';
import '../../models/txt_toc_rule.dart';
import '../../models/cache.dart';
import '../../models/keyboard_assist.dart';
import '../../models/rule_sub.dart';
import '../../models/source_subscription.dart';
import '../../models/search_book.dart';
import '../../models/download_task.dart';
import '../../models/search_keyword.dart';

// ─────────────────── TypeConverters ───────────────────

/// null String? → non-null String (empty string fallback)
class EmptyStringConverter extends TypeConverter<String, String?> {
  const EmptyStringConverter();
  @override
  String fromSql(String? fromDb) => fromDb ?? '';
  @override
  String? toSql(String value) => value.isEmpty ? null : value;
}

/// ReadConfig? ↔ JSON String?
class ReadConfigConverter extends TypeConverter<ReadConfig?, String?> {
  const ReadConfigConverter();
  @override
  ReadConfig? fromSql(String? fromDb) {
    if (fromDb == null) return null;
    try {
      return ReadConfig.fromJson(jsonDecode(fromDb) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  @override
  String? toSql(ReadConfig? value) {
    if (value == null) return null;
    return jsonEncode(value.toJson());
  }
}

/// SearchRule? ↔ JSON String?
class SearchRuleConverter extends TypeConverter<SearchRule?, String?> {
  const SearchRuleConverter();
  @override
  SearchRule? fromSql(String? fromDb) {
    if (fromDb == null) return null;
    try {
      return SearchRule.fromJson(jsonDecode(fromDb) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  @override
  String? toSql(SearchRule? value) =>
      value == null ? null : jsonEncode(value.toJson());
}

/// ExploreRule? ↔ JSON String?
class ExploreRuleConverter extends TypeConverter<ExploreRule?, String?> {
  const ExploreRuleConverter();
  @override
  ExploreRule? fromSql(String? fromDb) {
    if (fromDb == null) return null;
    try {
      return ExploreRule.fromJson(jsonDecode(fromDb) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  @override
  String? toSql(ExploreRule? value) =>
      value == null ? null : jsonEncode(value.toJson());
}

/// BookInfoRule? ↔ JSON String?
class BookInfoRuleConverter extends TypeConverter<BookInfoRule?, String?> {
  const BookInfoRuleConverter();
  @override
  BookInfoRule? fromSql(String? fromDb) {
    if (fromDb == null) return null;
    try {
      return BookInfoRule.fromJson(jsonDecode(fromDb) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  @override
  String? toSql(BookInfoRule? value) =>
      value == null ? null : jsonEncode(value.toJson());
}

/// TocRule? ↔ JSON String?
class TocRuleConverter extends TypeConverter<TocRule?, String?> {
  const TocRuleConverter();
  @override
  TocRule? fromSql(String? fromDb) {
    if (fromDb == null) return null;
    try {
      return TocRule.fromJson(jsonDecode(fromDb) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  @override
  String? toSql(TocRule? value) =>
      value == null ? null : jsonEncode(value.toJson());
}

/// ContentRule? ↔ JSON String?
class ContentRuleConverter extends TypeConverter<ContentRule?, String?> {
  const ContentRuleConverter();
  @override
  ContentRule? fromSql(String? fromDb) {
    if (fromDb == null) return null;
    try {
      return ContentRule.fromJson(jsonDecode(fromDb) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  @override
  String? toSql(ContentRule? value) =>
      value == null ? null : jsonEncode(value.toJson());
}

/// ReviewRule? ↔ JSON String?
class ReviewRuleConverter extends TypeConverter<ReviewRule?, String?> {
  const ReviewRuleConverter();
  @override
  ReviewRule? fromSql(String? fromDb) {
    if (fromDb == null) return null;
    try {
      return ReviewRule.fromJson(jsonDecode(fromDb) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  @override
  String? toSql(ReviewRule? value) =>
      value == null ? null : jsonEncode(value.toJson());
}

// ─────────────────── Tables ───────────────────

// ───────────── Books ─────────────
@UseRowClass(Book, generateInsertable: true)
class Books extends Table {
  TextColumn get bookUrl => text().named('bookUrl')();
  TextColumn get tocUrl =>
      text().named('tocUrl').nullable().map(const EmptyStringConverter())();
  TextColumn get origin =>
      text().nullable().map(const EmptyStringConverter())();
  TextColumn get originName =>
      text().named('originName').nullable().map(const EmptyStringConverter())();
  TextColumn get name => text()();
  TextColumn get author =>
      text().nullable().map(const EmptyStringConverter())();
  TextColumn get kind => text().nullable()();
  TextColumn get customTag => text().named('customTag').nullable()();
  TextColumn get coverUrl => text().named('coverUrl').nullable()();
  TextColumn get coverLocalPath => text().named('coverLocalPath').nullable()();
  TextColumn get customCoverUrl => text().named('customCoverUrl').nullable()();
  TextColumn get customCoverLocalPath =>
      text().named('customCoverLocalPath').nullable()();
  TextColumn get intro => text().nullable()();
  TextColumn get customIntro => text().named('customIntro').nullable()();
  TextColumn get charset => text().nullable()();
  IntColumn get type =>
      integer().named('type').withDefault(const Constant(0))();
  IntColumn get group =>
      integer().named('group').withDefault(const Constant(0))();
  TextColumn get latestChapterTitle =>
      text().named('latestChapterTitle').nullable()();
  IntColumn get latestChapterTime =>
      integer().named('latestChapterTime').withDefault(const Constant(0))();
  IntColumn get lastCheckTime =>
      integer().named('lastCheckTime').withDefault(const Constant(0))();
  IntColumn get lastCheckCount =>
      integer().named('lastCheckCount').withDefault(const Constant(0))();
  IntColumn get totalChapterNum =>
      integer().named('totalChapterNum').withDefault(const Constant(0))();
  TextColumn get durChapterTitle =>
      text().named('durChapterTitle').nullable()();
  IntColumn get chapterIndex =>
      integer().named('chapterIndex').withDefault(const Constant(0))();
  IntColumn get charOffset =>
      integer().named('charOffset').withDefault(const Constant(0))();
  RealColumn get visualOffsetPx =>
      real().named('visualOffsetPx').withDefault(const Constant(0.0))();
  TextColumn get readerAnchorJson =>
      text().named('readerAnchorJson').nullable()();
  IntColumn get durChapterTime =>
      integer().named('durChapterTime').withDefault(const Constant(0))();
  TextColumn get wordCount => text().named('wordCount').nullable()();
  BoolColumn get canUpdate =>
      boolean().named('canUpdate').withDefault(const Constant(true))();
  IntColumn get order =>
      integer().named('order').withDefault(const Constant(0))();
  IntColumn get originOrder =>
      integer().named('originOrder').withDefault(const Constant(0))();
  TextColumn get variable => text().nullable()();
  TextColumn get readConfig =>
      text().named('readConfig').nullable().map(const ReadConfigConverter())();
  IntColumn get syncTime =>
      integer().named('syncTime').withDefault(const Constant(0))();
  BoolColumn get isInBookshelf =>
      boolean().named('isInBookshelf').withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {bookUrl};
}

// ───────────── Chapters ─────────────
@UseRowClass(BookChapter, generateInsertable: true)
class Chapters extends Table {
  TextColumn get url => text()();
  TextColumn get title => text()();
  BoolColumn get isVolume =>
      boolean().named('isVolume').withDefault(const Constant(false))();
  TextColumn get baseUrl =>
      text().named('baseUrl').nullable().map(const EmptyStringConverter())();
  TextColumn get bookUrl => text().named('bookUrl')();
  IntColumn get index => integer().named('index')();
  BoolColumn get isVip =>
      boolean().named('isVip').withDefault(const Constant(false))();
  BoolColumn get isPay =>
      boolean().named('isPay').withDefault(const Constant(false))();
  TextColumn get resourceUrl => text().named('resourceUrl').nullable()();
  TextColumn get tag => text().nullable()();
  TextColumn get wordCount => text().named('wordCount').nullable()();
  IntColumn get start => integer().nullable()();
  IntColumn get end => integer().named('end').nullable()();
  TextColumn get startFragmentId =>
      text().named('startFragmentId').nullable()();
  TextColumn get endFragmentId => text().named('endFragmentId').nullable()();
  TextColumn get variable => text().nullable()();
  @override
  Set<Column> get primaryKey => {url};
}

// ───────────── Reader chapter content store ─────────────
class ReaderChapterContents extends Table {
  TextColumn get contentKey => text().named('contentKey')();
  TextColumn get origin => text()();
  TextColumn get bookUrl => text().named('bookUrl')();
  TextColumn get chapterUrl => text().named('chapterUrl')();
  IntColumn get chapterIndex => integer().named('chapterIndex')();
  TextColumn get content => text().nullable()();
  IntColumn get status =>
      integer().named('status').withDefault(const Constant(1))();
  TextColumn get failureMessage => text().named('failureMessage').nullable()();
  IntColumn get updatedAt => integer().named('updatedAt')();

  @override
  Set<Column> get primaryKey => {contentKey};
}

// ───────────── BookSources ─────────────
@UseRowClass(BookSource, generateInsertable: true)
class BookSources extends Table {
  TextColumn get bookSourceUrl => text().named('bookSourceUrl')();
  TextColumn get bookSourceName => text().named('bookSourceName')();
  IntColumn get bookSourceType =>
      integer().named('bookSourceType').withDefault(const Constant(0))();
  TextColumn get bookSourceGroup =>
      text().named('bookSourceGroup').nullable()();
  TextColumn get bookSourceComment =>
      text().named('bookSourceComment').nullable()();
  TextColumn get loginUrl => text().named('loginUrl').nullable()();
  TextColumn get loginUi => text().named('loginUi').nullable()();
  TextColumn get loginCheckJs => text().named('loginCheckJs').nullable()();
  TextColumn get coverDecodeJs => text().named('coverDecodeJs').nullable()();
  TextColumn get bookUrlPattern => text().named('bookUrlPattern').nullable()();
  TextColumn get header => text().nullable()();
  TextColumn get variableComment =>
      text().named('variableComment').nullable()();
  IntColumn get customOrder =>
      integer().named('customOrder').withDefault(const Constant(0))();
  IntColumn get weight => integer().withDefault(const Constant(0))();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  BoolColumn get enabledExplore =>
      boolean().named('enabledExplore').withDefault(const Constant(true))();
  BoolColumn get enabledCookieJar =>
      boolean().named('enabledCookieJar').withDefault(const Constant(true))();
  IntColumn get lastUpdateTime =>
      integer().named('lastUpdateTime').withDefault(const Constant(0))();
  IntColumn get respondTime =>
      integer().named('respondTime').withDefault(const Constant(180000))();
  TextColumn get jsLib => text().named('jsLib').nullable()();
  TextColumn get concurrentRate => text().named('concurrentRate').nullable()();
  TextColumn get exploreUrl => text().named('exploreUrl').nullable()();
  TextColumn get exploreScreen => text().named('exploreScreen').nullable()();
  TextColumn get searchUrl => text().named('searchUrl').nullable()();
  TextColumn get ruleSearch =>
      text().named('ruleSearch').nullable().map(const SearchRuleConverter())();
  TextColumn get ruleExplore =>
      text()
          .named('ruleExplore')
          .nullable()
          .map(const ExploreRuleConverter())();
  TextColumn get ruleBookInfo =>
      text()
          .named('ruleBookInfo')
          .nullable()
          .map(const BookInfoRuleConverter())();
  TextColumn get ruleToc =>
      text().named('ruleToc').nullable().map(const TocRuleConverter())();
  TextColumn get ruleContent =>
      text()
          .named('ruleContent')
          .nullable()
          .map(const ContentRuleConverter())();
  TextColumn get ruleReview =>
      text().named('ruleReview').nullable().map(const ReviewRuleConverter())();

  @override
  Set<Column> get primaryKey => {bookSourceUrl};
}

// ───────────── BookGroups ─────────────
@UseRowClass(BookGroup, generateInsertable: true)
class BookGroups extends Table {
  IntColumn get groupId => integer().named('groupId')();
  TextColumn get groupName => text().named('groupName')();
  IntColumn get order =>
      integer().named('order').withDefault(const Constant(0))();
  BoolColumn get show => boolean().withDefault(const Constant(true))();
  TextColumn get coverPath => text().named('coverPath').nullable()();
  BoolColumn get enableRefresh =>
      boolean().named('enableRefresh').withDefault(const Constant(true))();
  IntColumn get bookSort =>
      integer().named('bookSort').withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {groupId};
}

// ───────────── SearchHistory ─────────────
@DataClassName('SearchHistoryRow')
class SearchHistoryTable extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get keyword => text()();
  IntColumn get searchTime => integer().named('searchTime')();
}

// ───────────── ReplaceRules ─────────────
@UseRowClass(ReplaceRule, generateInsertable: true)
class ReplaceRules extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().nullable().map(const EmptyStringConverter())();
  TextColumn get pattern => text()();
  TextColumn get replacement =>
      text().nullable().map(const EmptyStringConverter())();
  TextColumn get scope => text().nullable()();
  BoolColumn get scopeTitle =>
      boolean().named('scopeTitle').withDefault(const Constant(false))();
  BoolColumn get scopeContent =>
      boolean().named('scopeContent').withDefault(const Constant(true))();
  TextColumn get excludeScope => text().named('excludeScope').nullable()();
  BoolColumn get isEnabled =>
      boolean().named('isEnabled').withDefault(const Constant(true))();
  BoolColumn get isRegex =>
      boolean().named('isRegex').withDefault(const Constant(true))();
  IntColumn get timeoutMillisecond =>
      integer().named('timeoutMillisecond').withDefault(const Constant(3000))();
  TextColumn get group => text().named('group').nullable()();
  IntColumn get order =>
      integer().named('order').withDefault(const Constant(0))();
}

// ───────────── Bookmarks ─────────────
@UseRowClass(Bookmark, generateInsertable: true)
class Bookmarks extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get time => integer()();
  TextColumn get bookName => text().named('bookName')();
  TextColumn get bookAuthor =>
      text().named('bookAuthor').nullable().map(const EmptyStringConverter())();
  IntColumn get chapterIndex =>
      integer().named('chapterIndex').withDefault(const Constant(0))();
  IntColumn get chapterPos =>
      integer().named('chapterPos').withDefault(const Constant(0))();
  TextColumn get chapterName =>
      text()
          .named('chapterName')
          .nullable()
          .map(const EmptyStringConverter())();
  TextColumn get bookUrl => text().named('bookUrl')();
  TextColumn get bookText =>
      text().named('bookText').nullable().map(const EmptyStringConverter())();
  TextColumn get content =>
      text().nullable().map(const EmptyStringConverter())();
}

// ───────────── Cookies ─────────────
@UseRowClass(Cookie, generateInsertable: true)
class Cookies extends Table {
  TextColumn get url => text()();
  TextColumn get cookie => text()();

  @override
  Set<Column> get primaryKey => {url};
}

// ───────────── DictRules ─────────────
@UseRowClass(DictRule, generateInsertable: true)
class DictRules extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get urlRule =>
      text().named('urlRule').nullable().map(const EmptyStringConverter())();
  TextColumn get showRule =>
      text().named('showRule').nullable().map(const EmptyStringConverter())();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  IntColumn get sortNumber =>
      integer().named('sortNumber').withDefault(const Constant(0))();
}

// ───────────── HttpTts ─────────────
@UseRowClass(HttpTTS, generateInsertable: true)
class HttpTtsTable extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get url => text()();
  TextColumn get contentType => text().named('contentType').nullable()();
  TextColumn get concurrentRate => text().named('concurrentRate').nullable()();
  TextColumn get loginUrl => text().named('loginUrl').nullable()();
  TextColumn get loginUi => text().named('loginUi').nullable()();
  TextColumn get header => text().nullable()();
  TextColumn get jsLib => text().named('jsLib').nullable()();
  BoolColumn get enabledCookieJar =>
      boolean().named('enabledCookieJar').withDefault(const Constant(false))();
  TextColumn get loginCheckJs => text().named('loginCheckJs').nullable()();
  IntColumn get lastUpdateTime =>
      integer().named('lastUpdateTime').withDefault(const Constant(0))();
}

// ───────────── ReadRecords ─────────────
@UseRowClass(ReadRecord, generateInsertable: true)
class ReadRecords extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get bookName => text().named('bookName')();
  TextColumn get deviceId => text().named('deviceId')();
  IntColumn get readTime =>
      integer().named('readTime').withDefault(const Constant(0))();
  IntColumn get lastRead =>
      integer().named('lastRead').withDefault(const Constant(0))();
}

// ───────────── Servers ─────────────
@UseRowClass(Server, generateInsertable: true)
class Servers extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get type => text()();
  TextColumn get config => text().nullable()();
  IntColumn get sortNumber =>
      integer().named('sortNumber').withDefault(const Constant(0))();
}

// ───────────── TxtTocRules ─────────────
@UseRowClass(TxtTocRule, generateInsertable: true)
class TxtTocRules extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get rule => text()();
  TextColumn get example => text().nullable()();
  IntColumn get serialNumber =>
      integer().named('serialNumber').withDefault(const Constant(-1))();
  BoolColumn get enable => boolean().withDefault(const Constant(true))();
}

// ───────────── Cache ─────────────
@UseRowClass(Cache, generateInsertable: true)
class CacheTable extends Table {
  TextColumn get key => text().named('key')();
  TextColumn get value => text().named('value').nullable()();
  IntColumn get deadline => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {key};
}

// ───────────── KeyboardAssists ─────────────
@UseRowClass(KeyboardAssist, generateInsertable: true)
class KeyboardAssists extends Table {
  TextColumn get key => text().named('key')();
  IntColumn get type => integer().withDefault(const Constant(0))();
  TextColumn get value =>
      text().named('value').nullable().map(const EmptyStringConverter())();
  IntColumn get serialNo =>
      integer().named('serialNo').withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {key};
}

// ───────────── RuleSubs ─────────────
@UseRowClass(RuleSub, generateInsertable: true)
class RuleSubs extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get url => text()();
  IntColumn get type => integer().withDefault(const Constant(0))();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  IntColumn get order =>
      integer().named('order').withDefault(const Constant(0))();
}

// ───────────── SourceSubscriptions ─────────────
@UseRowClass(SourceSubscription, generateInsertable: true)
class SourceSubscriptions extends Table {
  TextColumn get url => text()();
  TextColumn get name => text()();
  IntColumn get type => integer().withDefault(const Constant(0))();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  IntColumn get order =>
      integer().named('order').withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {url};
}

// ───────────── SearchBooks ─────────────
@UseRowClass(SearchBook, generateInsertable: true)
class SearchBooks extends Table {
  TextColumn get bookUrl => text().named('bookUrl')();
  TextColumn get name => text()();
  TextColumn get author => text().nullable()();
  TextColumn get kind => text().nullable()();
  TextColumn get coverUrl => text().named('coverUrl').nullable()();
  TextColumn get intro => text().nullable()();
  TextColumn get wordCount => text().named('wordCount').nullable()();
  TextColumn get latestChapterTitle =>
      text().named('latestChapterTitle').nullable()();
  TextColumn get origin =>
      text().nullable().map(const EmptyStringConverter())();
  TextColumn get originName => text().named('originName').nullable()();
  IntColumn get originOrder =>
      integer().named('originOrder').withDefault(const Constant(0))();
  IntColumn get type => integer().withDefault(const Constant(0))();
  IntColumn get addTime =>
      integer().named('addTime').withDefault(const Constant(0))();
  TextColumn get variable => text().nullable()();
  TextColumn get tocUrl => text().named('tocUrl').nullable()();

  @override
  Set<Column> get primaryKey => {bookUrl};
}

// ───────────── DownloadTasks ─────────────
@UseRowClass(DownloadTask, generateInsertable: true)
class DownloadTasks extends Table {
  TextColumn get bookUrl => text().named('bookUrl')();
  TextColumn get bookName => text().named('bookName')();
  IntColumn get startChapterIndex =>
      integer().named('startChapterIndex').withDefault(const Constant(0))();
  IntColumn get endChapterIndex =>
      integer().named('endChapterIndex').withDefault(const Constant(0))();
  IntColumn get currentChapterIndex =>
      integer().named('currentChapterIndex').withDefault(const Constant(0))();
  IntColumn get totalCount =>
      integer().named('totalChapterCount').withDefault(const Constant(0))();
  IntColumn get status => integer().withDefault(const Constant(0))();
  IntColumn get successCount =>
      integer().named('successCount').withDefault(const Constant(0))();
  IntColumn get errorCount =>
      integer().named('errorCount').withDefault(const Constant(0))();
  IntColumn get lastUpdateTime =>
      integer().named('addTime').withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {bookUrl};
}

// ───────────── SearchKeywords ─────────────
@UseRowClass(SearchKeyword, generateInsertable: true)
class SearchKeywords extends Table {
  TextColumn get word => text()();
  IntColumn get usage => integer().withDefault(const Constant(0))();
  IntColumn get lastUseTime =>
      integer().named('lastUseTime').withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {word};
}
