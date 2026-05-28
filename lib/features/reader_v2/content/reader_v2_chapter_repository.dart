import 'package:reader/core/database/dao/book_dao.dart';
import 'package:reader/core/database/dao/book_source_dao.dart';
import 'package:reader/core/database/dao/chapter_dao.dart';
import 'package:reader/core/database/dao/replace_rule_dao.dart';
import 'package:reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:reader/core/di/injection.dart';
import 'package:reader/core/models/book.dart';
import 'package:reader/core/models/book_source.dart';
import 'package:reader/core/models/chapter.dart';
import 'package:reader/core/models/replace_rule.dart';
import 'package:reader/core/services/book_source_service.dart';
import 'package:reader/core/services/reader_chapter_content_storage.dart';
import 'package:reader/core/services/reader_chapter_content_store.dart';

import 'reader_v2_content.dart';
import 'reader_v2_content_transformer.dart';
import 'reader_v2_processed_chapter.dart';

class ReaderV2ChapterRepositoryException implements Exception {
  const ReaderV2ChapterRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ReaderV2ChapterRepository {
  ReaderV2ChapterRepository({
    required this.book,
    List<BookChapter> initialChapters = const <BookChapter>[],
    BookDao? bookDao,
    ChapterDao? chapterDao,
    ReplaceRuleDao? replaceDao,
    BookSourceDao? sourceDao,
    ReaderChapterContentDao? contentDao,
    BookSourceService? service,
    int Function()? currentChineseConvert,
  }) : bookDao = bookDao ?? getIt<BookDao>(),
       chapterDao = chapterDao ?? getIt<ChapterDao>(),
       replaceDao =
           replaceDao ??
           (getIt.isRegistered<ReplaceRuleDao>()
               ? getIt<ReplaceRuleDao>()
               : null),
       sourceDao = sourceDao ?? getIt<BookSourceDao>(),
       contentDao =
           contentDao ??
           (getIt.isRegistered<ReaderChapterContentDao>()
               ? getIt<ReaderChapterContentDao>()
               : null),
       service = service ?? BookSourceService(),
       currentChineseConvert = currentChineseConvert ?? (() => 0),
       _chapters = List<BookChapter>.from(initialChapters);

  final Book book;
  final BookDao bookDao;
  final ChapterDao chapterDao;
  final ReplaceRuleDao? replaceDao;
  final BookSourceDao sourceDao;
  final ReaderChapterContentDao? contentDao;
  final BookSourceService service;
  final int Function() currentChineseConvert;
  final ReaderV2ContentTransformer _contentTransformer =
      const ReaderV2ContentTransformer();

  List<BookChapter> _chapters;
  BookSource? _source;
  final Map<int, ReaderV2Content> _contentCache = <int, ReaderV2Content>{};
  final Map<int, Future<ReaderV2Content>> _contentInFlight =
      <int, Future<ReaderV2Content>>{};
  int _contentCacheGeneration = 0;
  List<ReplaceRule>? _enabledRules;
  Future<List<ReplaceRule>>? _enabledRulesInFlight;

  List<BookChapter> get chapters => List<BookChapter>.unmodifiable(_chapters);
  int get chapterCount => _chapters.length;

  Future<List<BookChapter>> ensureChapters() async {
    if (_chapters.isNotEmpty) return chapters;
    _chapters = await chapterDao.getByBook(book.bookUrl);
    if (_chapters.isNotEmpty) return chapters;
    final source = await _ensureSource();
    if (source == null) {
      if (book.origin == 'local') {
        throw const ReaderV2ChapterRepositoryException('本地書籍章節目錄不存在，請重新匯入');
      }
      throw const ReaderV2ChapterRepositoryException('章節目錄載入失敗: 找不到書源');
    }
    final fetched = await service.getChapterList(source, book);
    if (fetched.isEmpty) {
      throw const ReaderV2ChapterRepositoryException('章節目錄載入失敗: 目錄為空');
    }
    for (var i = 0; i < fetched.length; i++) {
      fetched[i].index = i;
      fetched[i].bookUrl = book.bookUrl;
    }
    await chapterDao.insertChapters(fetched);
    _chapters = fetched;
    return chapters;
  }

  BookChapter? chapterAt(int chapterIndex) {
    if (chapterIndex < 0 || chapterIndex >= _chapters.length) return null;
    return _chapters[chapterIndex];
  }

  String titleFor(int chapterIndex) {
    return chapterAt(chapterIndex)?.title ?? '';
  }

  Future<ReaderV2Content> loadContent(int chapterIndex) async {
    await ensureChapters();
    final safeIndex = _normalizeChapterIndex(chapterIndex);
    final cached = _contentCache[safeIndex];
    if (cached != null) return cached;
    final inFlight = _contentInFlight[safeIndex];
    if (inFlight != null) return inFlight;
    late final Future<ReaderV2Content> task;
    task = _loadContentUncached(safeIndex, _contentCacheGeneration);
    _contentInFlight[safeIndex] = task;
    try {
      return await task;
    } finally {
      if (identical(_contentInFlight[safeIndex], task)) {
        _contentInFlight.remove(safeIndex);
      }
    }
  }

  Future<ReaderV2Content?> preloadContent(int chapterIndex) async {
    await ensureChapters();
    if (!_isValidChapterIndex(chapterIndex)) return null;
    return loadContent(chapterIndex);
  }

  ReaderV2Content? cachedContent(int chapterIndex) =>
      _contentCache[chapterIndex];

  void clearContentCache() {
    _contentCacheGeneration += 1;
    _source = null;
    _contentCache.clear();
    _contentInFlight.clear();
    _enabledRules = null;
    _enabledRulesInFlight = null;
  }

  Future<ReaderV2Content> _loadContentUncached(
    int chapterIndex,
    int cacheGeneration,
  ) async {
    final chapter = chapterAt(chapterIndex);
    if (chapter == null) {
      throw const ReaderV2ChapterRepositoryException('章節內容載入失敗: 找不到章節');
    }
    final loaded = await _loadViaV2ContentPipeline(
      chapterIndex,
      chapter,
      cacheGeneration,
    );
    if (loaded != null) {
      final content = ReaderV2Content.fromRaw(
        chapterIndex: chapterIndex,
        title: loaded.displayTitle,
        rawText: loaded.content,
      );
      if (cacheGeneration == _contentCacheGeneration) {
        _contentCache[chapterIndex] = content;
      }
      return content;
    }

    final content = ReaderV2Content.fromRaw(
      chapterIndex: chapterIndex,
      title: chapter.title,
      rawText: (chapter.content ?? '').trim(),
    );
    if (cacheGeneration == _contentCacheGeneration) {
      _contentCache[chapterIndex] = content;
    }
    return content;
  }

  Future<List<ReplaceRule>> _ensureEnabledReplaceRules() {
    final dao = replaceDao;
    if (dao == null || !book.getUseReplaceRule()) {
      return Future<List<ReplaceRule>>.value(const <ReplaceRule>[]);
    }
    final cached = _enabledRules;
    if (cached != null) return Future<List<ReplaceRule>>.value(cached);
    final inFlight = _enabledRulesInFlight;
    if (inFlight != null) return inFlight;
    final cacheGeneration = _contentCacheGeneration;
    late final Future<List<ReplaceRule>> task;
    task = () async {
      try {
        final rules = await dao.getEnabledForBook(book.name, book.origin);
        if (cacheGeneration == _contentCacheGeneration) {
          _enabledRules = rules;
        }
        return rules;
      } finally {
        if (identical(_enabledRulesInFlight, task)) {
          _enabledRulesInFlight = null;
        }
      }
    }();
    _enabledRulesInFlight = task;
    return task;
  }

  Future<BookSource?> _ensureSource() async {
    if (_source != null) return _source;
    if (book.origin.isEmpty || book.origin == 'local') return null;
    final cacheGeneration = _contentCacheGeneration;
    final source = await sourceDao.getByUrl(book.origin);
    if (cacheGeneration == _contentCacheGeneration) {
      _source = source;
    }
    return source;
  }

  Future<ReaderV2ProcessedChapter?> _loadViaV2ContentPipeline(
    int chapterIndex,
    BookChapter chapter,
    int cacheGeneration,
  ) async {
    final contentDao = this.contentDao;
    if (contentDao == null) return null;
    final storage = ReaderChapterContentStorage.withMaterializer(
      book: book,
      contentStore: ReaderChapterContentStore(
        chapterDao: chapterDao,
        contentDao: contentDao,
      ),
      sourceDao: sourceDao,
      service: service,
      getSource:
          () => cacheGeneration == _contentCacheGeneration ? _source : null,
      setSource: (source) {
        if (cacheGeneration == _contentCacheGeneration) {
          _source = source;
        }
      },
      resolveNextChapterUrl: (index) => chapterAt(index + 1)?.url,
    );
    final prepared = await storage.read(
      chapterIndex: chapterIndex,
      chapter: chapter,
      saveChapterMetadata: book.origin != 'local',
    );
    if (prepared.isFailed) {
      throw ReaderV2ChapterRepositoryException(
        (prepared.failureMessage ?? prepared.content).trim(),
      );
    }
    final enabledRules = await _ensureEnabledReplaceRules();
    return _contentTransformer.process(
      book: book,
      chapter: chapter,
      rawContent: prepared.content,
      enabledRules: enabledRules,
      chineseConvertType: currentChineseConvert(),
    );
  }

  bool _isValidChapterIndex(int chapterIndex) {
    return chapterIndex >= 0 && chapterIndex < _chapters.length;
  }

  int _normalizeChapterIndex(int chapterIndex) {
    if (_chapters.isEmpty) return chapterIndex < 0 ? 0 : chapterIndex;
    return chapterIndex.clamp(0, _chapters.length - 1).toInt();
  }
}
