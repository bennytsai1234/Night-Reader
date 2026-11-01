import 'dart:async';

import 'package:dio/dio.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/replace_rule_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/core/local_book/local_book_formats.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/replace_rule.dart';
import 'package:night_reader/core/services/book_source_service.dart';
import 'package:night_reader/core/services/reader_chapter_content_storage.dart';
import 'package:night_reader/core/services/reader_chapter_content_store.dart';

import 'package:night_reader/features/reader_v2/hybrid/progress/chapter_shares.dart';

import 'reader_v2_content.dart';
import 'reader_v2_content_transformer.dart';

typedef ReaderV2TestContentLoader = Future<String?> Function(
  int chapterIndex,
  BookChapter chapter,
);

final class ReaderV2ContentUnavailableException implements Exception {
  const ReaderV2ContentUnavailableException(this.message);

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
    this.contentLoader,
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

  /// Test-only seam. When absent, the production content pipeline is
  /// unchanged. A supplied loader may hold a chapter future to reproduce a
  /// deterministic in-flight state without changing rendering behaviour.
  final ReaderV2TestContentLoader? contentLoader;
  final ReaderV2ContentTransformer _contentTransformer =
      const ReaderV2ContentTransformer();

  List<BookChapter> _chapters;
  BookSource? _source;
  static const int _maxContentCacheSize = 20;
  final Map<int, ReaderV2Content> _contentCache = <int, ReaderV2Content>{};
  final Map<int, Future<ReaderV2Content>> _contentInFlight =
      <int, Future<ReaderV2Content>>{};
  int _contentCacheGeneration = 0;
  int _contentGeneration = 0;
  final Map<int, String> _materializedContentIdentities = <int, String>{};
  List<ReplaceRule>? _enabledRules;
  Future<List<ReplaceRule>>? _enabledRulesInFlight;
  // reloadContent owns destructive semantic-cache refreshes. Keep one
  // repository transaction active at a time so a successor can only
  // snapshot a fully committed or fully rolled-back world.
  Future<void> _reloadTail = Future<void>.value();

  List<BookChapter> get chapters => List<BookChapter>.unmodifiable(_chapters);
  int get chapterCount => _chapters.length;

  /// 同時有好幾處要目錄（開書排版、讀每章長度）時共用同一次載入，不會
  /// 向書源抓兩次。
  Future<List<BookChapter>> ensureChapters() {
    if (_chapters.isNotEmpty) return Future.value(chapters);
    return _chaptersInFlight ??= _loadChapters().whenComplete(
      () => _chaptersInFlight = null,
    );
  }

  Future<List<BookChapter>>? _chaptersInFlight;

  Future<List<BookChapter>> _loadChapters() async {
    _chapters = await chapterDao.getByBook(book.bookUrl);
    if (_chapters.isNotEmpty) return chapters;
    final source = await _ensureSource();
    if (source == null) {
      if (book.origin == 'local') {
        throw const ReaderV2ContentUnavailableException('本地書籍章節目錄不存在，請重新匯入');
      }
      throw const ReaderV2ContentUnavailableException('章節目錄載入失敗: 找不到書源');
    }
    final fetched = await _loadChapterListFromSource(source);
    if (fetched.isEmpty) {
      throw const ReaderV2ContentUnavailableException('章節目錄載入失敗: 目錄為空');
    }
    for (var i = 0; i < fetched.length; i++) {
      fetched[i].index = i;
      fetched[i].bookUrl = book.bookUrl;
    }
    await chapterDao.insertChapters(fetched);
    _chapters = fetched;
    return chapters;
  }

  /// 每章佔全書多少（全書進度用）。本地書照每章在檔案裡的位元組範圍；
  /// 網路書照下載好的正文的位元組數，還沒下載的章照已下載的平均。分卷
  /// 標題沒有正文，佔 0。
  Future<ReaderV2ChapterShares> loadChapterShares() async {
    final chapters = _chapters;
    if (chapters.isEmpty) return const ReaderV2ChapterShares.even(0);
    Map<String, int> stored = const <String, int>{};
    if (book.origin != 'local') {
      stored =
          await contentDao?.getStoredContentBytes(
            origin: book.origin,
            bookUrl: book.bookUrl,
          ) ??
          const <String, int>{};
    }
    return ReaderV2ChapterShares.fromLengths([
      for (final chapter in chapters)
        if (chapter.isVolume)
          0
        else if (chapter.start != null && chapter.end != null)
          chapter.end! - chapter.start!
        else
          stored[chapter.url],
    ]);
  }

  Future<List<BookChapter>> _loadChapterListFromSource(
    BookSource source,
  ) async {
    try {
      return await service.getChapterList(source, book);
    } on DioException catch (error) {
      if (error.type == DioExceptionType.cancel) rethrow;
      final status = error.response?.statusCode;
      throw ReaderV2ContentUnavailableException(
        status == null ? '章節目錄載入失敗: 網路錯誤' : '章節目錄載入失敗: 伺服器回應 $status',
      );
    } on AppException catch (error) {
      throw ReaderV2ContentUnavailableException('章節目錄載入失敗: ${error.message}');
    }
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
    final cached = _contentCache.remove(safeIndex);
    if (cached != null) {
      _contentCache[safeIndex] = cached;
      return cached;
    }
    final inFlight = _contentInFlight[safeIndex];
    if (inFlight != null) return inFlight;
    late final Future<ReaderV2Content> task;
    task = _loadContentUncached(safeIndex, _contentCacheGeneration);
    _contentInFlight[safeIndex] = task;
    try {
      return await task;
    } finally {
      if (identical(_contentInFlight[safeIndex], task)) {
        unawaited(_contentInFlight.remove(safeIndex));
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

  /// Monotonic generation for the committed semantic document.
  ///
  /// This is intentionally separate from [_contentCacheGeneration], which is
  /// an internal async/cache fence and may advance during a failed refresh.
  /// Consumers must only invalidate semantic coordinates when this committed
  /// generation changes.
  int get contentGeneration => _contentGeneration;

  /// Refreshes semantic content without destroying the last committed world
  /// if the replacement cannot be materialized.
  ///
  /// [_contentCacheGeneration] remains monotonic even on rollback so abandoned
  /// async work cannot become current later. [contentGeneration] advances after
  /// a successful explicit refresh, or when a reacquired materialized chapter
  /// proves that its committed identity changed outside this repository.
  ///
  /// [refetch] 先向書源重抓這一章、成功才換掉存著的正文（書源回了擋爬蟲頁
  /// 或不完整的正文時用）；抓不到就丟出 [ReaderV2ContentUnavailableException]，
  /// 存著的正文與閱讀中的內容都不變。
  Future<ReaderV2Content> reloadContent(
    int chapterIndex, {
    bool refetch = false,
  }) {
    final result = Completer<ReaderV2Content>();
    _reloadTail = _reloadTail.then((_) async {
      try {
        result.complete(
          await _reloadContentTransaction(chapterIndex, refetch: refetch),
        );
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  Future<ReaderV2Content> _reloadContentTransaction(
    int chapterIndex, {
    required bool refetch,
  }) async {
    await ensureChapters();
    final safeIndex = _normalizeChapterIndex(chapterIndex);
    final previousCache = Map<int, ReaderV2Content>.from(_contentCache);
    final previousSource = _source;
    final previousRules = _enabledRules;
    final previousIdentities = Map<int, String>.from(
      _materializedContentIdentities,
    );

    _contentCacheGeneration += 1;
    final refreshGeneration = _contentCacheGeneration;
    _source = null;
    _contentCache.clear();
    _contentInFlight.clear();
    _materializedContentIdentities.clear();
    _enabledRules = null;
    _enabledRulesInFlight = null;

    var materialized = false;
    try {
      if (refetch) await _refetchStoredContent(safeIndex, refreshGeneration);
      final content = await loadContent(safeIndex);
      materialized = true;
      if (_contentCacheGeneration == refreshGeneration) {
        _contentGeneration += 1;
      }
      return content;
    } finally {
      if (!materialized && _contentCacheGeneration == refreshGeneration) {
        // Invalidate every async task started by the failed refresh before
        // restoring the last committed semantic world.
        _contentCacheGeneration += 1;
        _source = previousSource;
        _contentCache
          ..clear()
          ..addAll(previousCache);
        _contentInFlight.clear();
        _materializedContentIdentities
          ..clear()
          ..addAll(previousIdentities);
        _enabledRules = previousRules;
        _enabledRulesInFlight = null;
      }
    }
  }

  Future<ReaderV2Content> _loadContentUncached(
    int chapterIndex,
    int cacheGeneration,
  ) async {
    final chapter = chapterAt(chapterIndex);
    if (chapter == null) {
      throw const ReaderV2ContentUnavailableException('章節內容載入失敗: 找不到章節');
    }
    final testLoader = contentLoader;
    if (testLoader != null) {
      final rawContent = await testLoader(chapterIndex, chapter);
      final content = ReaderV2Content.fromRaw(
        chapterIndex: chapterIndex,
        title: chapter.title,
        rawText: rawContent ?? chapter.content ?? '',
      );
      if (cacheGeneration == _contentCacheGeneration) {
        _writeToContentCache(chapterIndex, content);
      }
      return content;
    }
    final loaded = await _loadViaV2ContentPipeline(
      chapterIndex,
      chapter,
      cacheGeneration,
    );
    if (loaded != null) {
      if (cacheGeneration == _contentCacheGeneration) {
        _writeToContentCache(chapterIndex, loaded);
      }
      return loaded;
    }

    final content = ReaderV2Content.fromRaw(
      chapterIndex: chapterIndex,
      title: chapter.title,
      rawText: (chapter.content ?? '').trim(),
    );
    if (cacheGeneration == _contentCacheGeneration) {
      _writeToContentCache(chapterIndex, content);
    }
    return content;
  }

  void _writeToContentCache(int chapterIndex, ReaderV2Content content) {
    final previousIdentity = _materializedContentIdentities[chapterIndex];
    if (previousIdentity != null && previousIdentity != content.contentHash) {
      // Persistent acquisition can change outside the active Reader (for
      // example a downloader refresh). The content owner recognizes that
      // identity transition here; Hybrid must never infer it from layout.
      _contentGeneration += 1;
    }
    _materializedContentIdentities[chapterIndex] = content.contentHash;

    _contentCache.remove(chapterIndex);
    if (_contentCache.length >= _maxContentCacheSize) {
      _contentCache.remove(_contentCache.keys.first);
    }
    _contentCache[chapterIndex] = content;
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

  Future<void> _refetchStoredContent(
    int chapterIndex,
    int cacheGeneration,
  ) async {
    final chapter = chapterAt(chapterIndex);
    final storage = _contentStorage(cacheGeneration);
    if (chapter == null || storage == null) return;
    final fetched = await storage.read(
      chapterIndex: chapterIndex,
      chapter: chapter,
      forceRefresh: true,
      saveChapterMetadata: book.origin != 'local',
    );
    if (fetched.isFailed) {
      throw ReaderV2ContentUnavailableException(
        (fetched.failureMessage ?? fetched.content).trim(),
      );
    }
  }

  ReaderChapterContentStorage? _contentStorage(int cacheGeneration) {
    final contentDao = this.contentDao;
    if (contentDao == null) return null;
    return ReaderChapterContentStorage.withMaterializer(
      book: book,
      contentStore: ReaderChapterContentStore(
        chapterDao: chapterDao,
        contentDao: contentDao,
      ),
      sourceDao: sourceDao,
      service: service,
      getSource: () =>
          cacheGeneration == _contentCacheGeneration ? _source : null,
      setSource: (source) {
        if (cacheGeneration == _contentCacheGeneration) {
          _source = source;
        }
      },
      resolveNextChapterUrl: (index) => chapterAt(index + 1)?.url,
    );
  }

  Future<ReaderV2Content?> _loadViaV2ContentPipeline(
    int chapterIndex,
    BookChapter chapter,
    int cacheGeneration,
  ) async {
    final localExtension = localBookExtensionFromPath(book.bookUrl);
    if (book.origin == 'local' &&
        book.bookUrl.startsWith('local://') &&
        localExtension.isNotEmpty &&
        !isSupportedLocalBookPath(book.bookUrl)) {
      throw const ReaderV2ContentUnavailableException(
        '本地書格式不受支援，請使用 TXT 或 EPUB 檔案',
      );
    }
    final storage = _contentStorage(cacheGeneration);
    if (storage == null) return null;
    final prepared = await storage.read(
      chapterIndex: chapterIndex,
      chapter: chapter,
      saveChapterMetadata: book.origin != 'local',
    );
    if (prepared.isFailed) {
      throw ReaderV2ContentUnavailableException(
        (prepared.failureMessage ?? prepared.content).trim(),
      );
    }
    final enabledRules = await _ensureEnabledReplaceRules();
    try {
      return await _contentTransformer.process(
        chapterIndex: chapterIndex,
        book: book,
        chapter: chapter,
        rawContent: prepared.content,
        enabledRules: enabledRules,
        chineseConvertType: currentChineseConvert(),
      );
    } on ReaderV2ContentTransformException catch (error) {
      throw ReaderV2ContentUnavailableException(error.message);
    }
  }

  bool _isValidChapterIndex(int chapterIndex) {
    return chapterIndex >= 0 && chapterIndex < _chapters.length;
  }

  int _normalizeChapterIndex(int chapterIndex) {
    if (_chapters.isEmpty) return chapterIndex < 0 ? 0 : chapterIndex;
    return chapterIndex.clamp(0, _chapters.length - 1).toInt();
  }
}
