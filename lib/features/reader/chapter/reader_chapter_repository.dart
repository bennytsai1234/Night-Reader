import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/bookmark_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/highlight_dao.dart';
import 'package:night_reader/core/database/dao/replace_rule_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/engine/app_event_bus.dart';
import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/core/local_book/local_book_formats.dart';
import 'package:night_reader/core/models/book/chapter_alignment.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/core/models/replace_rule.dart';
import 'package:night_reader/core/diagnostics/app_log_service.dart';
import 'package:night_reader/core/storage/book_illustration_storage.dart';
import 'package:night_reader/core/source/book_source_service.dart';
import 'package:night_reader/core/local_book/local_book_service.dart';
import 'package:night_reader/core/storage/reader_chapter_content_storage.dart';
import 'package:night_reader/core/storage/reader_chapter_content_store.dart';

import 'package:night_reader/features/reader/session/reader_location.dart';
import 'package:night_reader/features/reader/text_view/progress/reader_chapter_shares.dart';

import 'reader_content.dart';
import 'reader_content_transformer.dart';

typedef ReaderTestContentLoader = Future<String?> Function(
  int chapterIndex,
  BookChapter chapter,
);

/// 開書時目錄換過（本地 EPUB 重轉、TXT 重新分章），開書前拿到的位置（舊
/// 目錄的座標）換成現在目錄的（[ReaderChapterRepository.takeLocationRefresh]）。
/// [byPosition] 是照檔案裡的位置換算的（TXT），章名也跟著換了，不能再照舊
/// 章名對。
typedef ReaderLocationRefresh = ({
  ReaderLocation Function(ReaderLocation location) map,
  bool byPosition,
});

final class ReaderContentUnavailableException implements Exception {
  const ReaderContentUnavailableException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ReaderChapterRepository {
  ReaderChapterRepository({
    required this.book,
    List<BookChapter> initialChapters = const <BookChapter>[],
    BookDao? bookDao,
    ChapterDao? chapterDao,
    ReplaceRuleDao? replaceDao,
    BookSourceDao? sourceDao,
    ReaderChapterContentDao? contentDao,
    BookmarkDao? bookmarkDao,
    HighlightDao? highlightDao,
    BookSourceService? service,
    int Function()? currentChineseConvert,
    bool Function()? currentShowIllustrations,
    this.onReplaceRuleDisabled,
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
       bookmarkDao =
           bookmarkDao ??
           (getIt.isRegistered<BookmarkDao>() ? getIt<BookmarkDao>() : null),
       highlightDao =
           highlightDao ??
           (getIt.isRegistered<HighlightDao>() ? getIt<HighlightDao>() : null),
       service = service ?? BookSourceService(),
       currentChineseConvert = currentChineseConvert ?? (() => 0),
       currentShowIllustrations = currentShowIllustrations ?? (() => false),
       _chapters = List<BookChapter>.from(initialChapters),
       _origin = book.origin,
       _txtCheckedBefore = LocalBookService().txtChaptersChecked(book) {
    if (!book.isLocal) {
      _moves = AppEventBus()
          .onName(AppEventBus.sourceMoved)
          .listen((event) => _followMove(event.data as SourceMovedEvent));
    }
  }

  final Book book;
  final BookDao bookDao;
  final ChapterDao chapterDao;
  final ReplaceRuleDao? replaceDao;
  final BookSourceDao sourceDao;
  final ReaderChapterContentDao? contentDao;

  /// 本地 TXT 重新分章時書籤與標註跟著換到新目錄。
  final BookmarkDao? bookmarkDao;
  final HighlightDao? highlightDao;
  final BookSourceService service;
  final int Function() currentChineseConvert;

  /// 「顯示插圖」開著沒（ADR 0050）。
  final bool Function() currentShowIllustrations;

  /// 套用正文時有規則跑太久、被停用了（[disableTimedOutRule]），閱讀器拿來
  /// 提示讀者。
  final void Function(ReplaceRule rule)? onReplaceRuleDisabled;

  /// Test-only seam. When absent, the production content pipeline is
  /// unchanged. A supplied loader may hold a chapter future to reproduce a
  /// deterministic in-flight state without changing rendering behaviour.
  final ReaderTestContentLoader? contentLoader;
  final ReaderContentTransformer _contentTransformer =
      const ReaderContentTransformer();

  List<BookChapter> _chapters;
  BookSource? _source;

  /// 別處換了這本書的書源網址、這裡也換上之後呼叫（[_followMove]）：正文裡
  /// 的插圖照書本資料夾的路徑排好，閱讀器照新網址重排畫面上的章。
  void Function()? onOriginMoved;

  /// 這裡抓章、讀正文用的書源網址。書可能和其他頁面共用、那邊先改了
  /// [book] 的網址，照這個比對是不是這本書的書源搬家。
  String _origin;
  StreamSubscription<AppEvent>? _moves;
  static const int _maxContentCacheSize = 20;
  final Map<int, ReaderContent> _contentCache = <int, ReaderContent>{};
  final Map<int, Future<ReaderContent>> _contentInFlight =
      <int, Future<ReaderContent>>{};
  int _contentCacheGeneration = 0;
  int _contentGeneration = 0;
  final Map<int, String> _materializedContentIdentities = <int, String>{};
  List<ReplaceRule>? _enabledRules;
  Future<List<ReplaceRule>>? _enabledRulesInFlight;

  /// 這本書要換目錄了（改編碼）：已經在讀的章照樣排給畫面，但不再存回正文
  /// 表，免得把舊編碼的正文寫回剛清掉的目錄底下。
  bool _retired = false;

  /// 目錄要換掉之前呼叫（[changeCharset]）：停止存正文；停止寫進度。
  void retire() {
    _retired = true;
  }

  /// 換目錄失敗、閱讀器照舊時恢復。
  void resume() {
    _retired = false;
  }

  /// 替換規則表每改一次就加一（[_forgetEnabledRules]）：快取的規則清單只在
  /// 讀的期間沒改過時留著，重載失敗也不放回改之前的那份。
  int _rulesRevision = 0;
  StreamSubscription<void>? _ruleChanges;
  // reloadContent owns destructive semantic-cache refreshes. Keep one
  // repository transaction active at a time so a successor can only
  // snapshot a fully committed or fully rolled-back world.
  Future<void> _reloadTail = Future<void>.value();

  List<BookChapter> get chapters => List<BookChapter>.unmodifiable(_chapters);
  int get chapterCount => _chapters.length;

  /// 同時有好幾處要目錄（開書排版、讀每章長度）時共用同一次載入，不會
  /// 向書源抓兩次。
  ///
  /// 本地書開書時一定先對一次目錄（[_syncLocalChapters]：EPUB 的轉法版本、
  /// TXT 的分章版本），帶著目錄開書（書籍詳情傳進來的）也一樣，讀章前章節
  /// 範圍已經是新的。
  Future<List<BookChapter>> ensureChapters() {
    if (_chapters.isNotEmpty && (!book.isLocal || _localChaptersChecked)) {
      return Future.value(chapters);
    }
    return _chaptersInFlight ??=
        (_chapters.isNotEmpty
                ? _syncLocalChapters().then((_) => chapters)
                : _loadChapters())
            .whenComplete(() => _chaptersInFlight = null);
  }

  Future<List<BookChapter>>? _chaptersInFlight;
  bool _localChaptersChecked = false;

  Future<List<BookChapter>> _loadChapters() async {
    _chapters = await chapterDao.getByBook(book.bookUrl);
    if (_chapters.isNotEmpty) {
      if (book.isLocal) await _syncLocalChapters();
      return chapters;
    }
    final source = await _ensureSource();
    if (source == null) {
      if (book.isLocal) {
        throw const ReaderContentUnavailableException('本地書籍章節目錄不存在，請重新匯入');
      }
      throw const ReaderContentUnavailableException('章節目錄載入失敗: 找不到書源');
    }
    final fetched = await _loadChapterListFromSource(source);
    if (fetched.isEmpty) {
      throw const ReaderContentUnavailableException('章節目錄載入失敗: 目錄為空');
    }
    for (var i = 0; i < fetched.length; i++) {
      fetched[i].index = i;
      fetched[i].bookUrl = book.bookUrl;
    }
    await chapterDao.insertChapters(fetched);
    _chapters = fetched;
    return chapters;
  }

  /// 開書時 EPUB 重轉、換掉的舊目錄（[_syncEpubChapters]），開書的位置照它
  /// 對到新目錄一次（[takeLocationRefresh]）。
  List<BookChapter>? _replacedChapters;

  /// 開書時 TXT 重新分章的對照（[_syncTxtChapters]），開書的位置照它換算
  /// 一次（[takeLocationRefresh]）。
  TxtChapterRemap? _txtRemap;

  /// 建立時這本 TXT 這次 App 執行期間已經對過分章版本：開書拿到的位置都是
  /// 現在目錄的座標，之後拿到的對照不再套用。
  final bool _txtCheckedBefore;

  /// 開書前拿到的位置（開書的位置、開書前的跳章）換成現在目錄的座標：開書
  /// 時目錄換過才有，只拿一次；沒換過是 null。EPUB 重轉、目錄變了（例如多了
  /// 分卷）照章名對過去；TXT 重新分章照檔案裡的位置換算章與章內字數，錨點
  /// 清掉，畫面上的位移歸零（換算前後都在章首時照舊，例如照章節開書）。
  ReaderLocationRefresh? takeLocationRefresh() {
    final remap = _txtRemap;
    final old = _replacedChapters;
    _txtRemap = null;
    _replacedChapters = null;
    if (remap != null) {
      return (
        map: (location) {
          final mapped = remap.map(location.chapterIndex, location.charOffset);
          final atStart = location.charOffset == 0 && mapped.charOffset == 0;
          return location.copyWith(
            chapterIndex: mapped.index,
            charOffset: mapped.charOffset,
            visualOffsetPx: atStart ? location.visualOffsetPx : 0.0,
            clearContentIdentity: true,
          );
        },
        byPosition: true,
      );
    }
    if (old != null) {
      return (
        map: (location) => location.copyWith(
          chapterIndex: _alignToRefreshed(old, location.chapterIndex),
        ),
        byPosition: false,
      );
    }
    return null;
  }

  int _alignToRefreshed(List<BookChapter> old, int index) {
    if (old.isEmpty || _chapters.isEmpty) return index;
    final safe = index.clamp(0, old.length - 1);
    return alignChapterIndex(
      oldIndex: safe,
      oldTitle: old[safe].title,
      oldTotalCount: old.length,
      newChapters: _chapters,
    );
  }

  bool get _isLocalTxt =>
      localBookExtensionFromPath(LocalBookService.filePathOf(book)) == 'txt';

  /// 本地書的目錄對上現在的原檔：TXT 照分章版本
  /// （[LocalBookService.ensureTxtChapters]），EPUB 照轉好的文字
  /// （[LocalBookService.syncEpubChapters]）。
  Future<void> _syncLocalChapters() async {
    try {
      if (_isLocalTxt) {
        await _syncTxtChapters();
      } else {
        await _syncEpubChapters();
      }
    } finally {
      _localChaptersChecked = true;
    }
  }

  Future<void> _syncTxtChapters() async {
    try {
      final synced = await LocalBookService().ensureTxtChapters(
        book,
        bookDao: bookDao,
        chapterDao: chapterDao,
        bookmarkDao: bookmarkDao,
        highlightDao: highlightDao,
        contentDao: contentDao,
      );
      if (synced.chapters.isNotEmpty) _chapters = synced.chapters;
      if (!_txtCheckedBefore) _txtRemap = synced.remap ?? _txtRemap;
    } catch (error, stackTrace) {
      // 對不了就照現有的目錄開書，下次開書再對。
      AppLog.e('TXT 重新分章失敗', error: error, stackTrace: stackTrace);
    }
  }

  /// 本地 EPUB 的目錄對上現在轉好的文字（[LocalBookService.syncEpubChapters]）。
  Future<void> _syncEpubChapters() async {
    try {
      final synced = await LocalBookService().syncEpubChapters(
        book,
        _chapters,
        bookDao: bookDao,
        chapterDao: chapterDao,
        contentDao: contentDao,
      );
      _chapters = synced.chapters;
      _replacedChapters = synced.replaced ?? _replacedChapters;
    } on FileSystemException catch (error) {
      // 對不了就照現有的目錄開書，下次開書再對。
      AppLog.w('EPUB 章節範圍對不上檔案：$error');
    }
  }

  /// 每章佔全書多少（全書進度用）。本地書照每章在檔案裡的位元組範圍；
  /// 網路書照下載好的正文的位元組數，還沒下載的章照已下載的平均。分卷
  /// 標題沒有正文，佔 0。
  Future<ReaderChapterShares> loadChapterShares() async {
    final chapters = _chapters;
    if (chapters.isEmpty) return const ReaderChapterShares.even(0);
    Map<String, int> stored = const <String, int>{};
    if (!book.isLocal) {
      stored =
          await contentDao?.getStoredContentBytes(
            origin: book.origin,
            bookUrl: book.bookUrl,
          ) ??
          const <String, int>{};
    }
    return ReaderChapterShares.fromLengths([
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
      throw ReaderContentUnavailableException(
        status == null ? '章節目錄載入失敗: 網路錯誤' : '章節目錄載入失敗: 伺服器回應 $status',
      );
    } on AppException catch (error) {
      throw ReaderContentUnavailableException('章節目錄載入失敗: ${error.message}');
    }
  }

  BookChapter? chapterAt(int chapterIndex) {
    if (chapterIndex < 0 || chapterIndex >= _chapters.length) return null;
    return _chapters[chapterIndex];
  }

  String titleFor(int chapterIndex) {
    return chapterAt(chapterIndex)?.title ?? '';
  }

  /// 已經載好的這一章排好的章名：套過標題規則與繁簡轉換（同 Legado 頁首
  /// 頁尾與選單用的章名）；還沒載入時傳回 null。
  String? displayTitleFor(int chapterIndex) {
    final title = _contentCache[chapterIndex]?.title;
    return title == null || title.isEmpty ? null : title;
  }

  Future<ReaderContent> loadContent(int chapterIndex) async {
    await ensureChapters();
    final safeIndex = _normalizeChapterIndex(chapterIndex);
    final cached = _contentCache.remove(safeIndex);
    if (cached != null) {
      _contentCache[safeIndex] = cached;
      return cached;
    }
    final inFlight = _contentInFlight[safeIndex];
    if (inFlight != null) return inFlight;
    late final Future<ReaderContent> task;
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

  Future<ReaderContent?> preloadContent(int chapterIndex) async {
    await ensureChapters();
    if (!_isValidChapterIndex(chapterIndex)) return null;
    return loadContent(chapterIndex);
  }

  ReaderContent? cachedContent(int chapterIndex) => _contentCache[chapterIndex];

  /// 排出第 [chapterIndex] 章、身分是 [contentHash] 的那份正文時用的原文
  /// （規則套用前、存著的樣子）；那份正文已經不在快取裡或換過了時是 null。
  /// 選字「隱藏」「替換」照它找原文：存著的正文換過（單章借源、重新取得
  /// 本章）而畫面還沒換時，不會拿新的原文去對舊的字。
  String? rawContentOf(int chapterIndex, String contentHash) {
    final raw = _rawContents[chapterIndex];
    return raw != null &&
            raw.contentHash == contentHash &&
            _contentCache[chapterIndex]?.contentHash == contentHash
        ? raw.raw
        : null;
  }

  /// 快取裡每一章正文是照哪份原文排的（[rawContentOf]）。
  final Map<int, ({String contentHash, String raw})> _rawContents = {};

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
  /// 或不完整的正文時用）；抓不到就丟出 [ReaderContentUnavailableException]，
  /// 存著的正文與閱讀中的內容都不變。
  Future<ReaderContent> reloadContent(
    int chapterIndex, {
    bool refetch = false,
  }) {
    final result = Completer<ReaderContent>();
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

  Future<ReaderContent> _reloadContentTransaction(
    int chapterIndex, {
    required bool refetch,
  }) async {
    await ensureChapters();
    final safeIndex = _normalizeChapterIndex(chapterIndex);
    final previousCache = Map<int, ReaderContent>.from(_contentCache);
    final previousRaw = Map<int, ({String contentHash, String raw})>.from(
      _rawContents,
    );
    final previousSource = _source;
    final previousRules = _enabledRules;
    final previousRulesRevision = _rulesRevision;
    final previousIdentities = Map<int, String>.from(
      _materializedContentIdentities,
    );

    _contentCacheGeneration += 1;
    final refreshGeneration = _contentCacheGeneration;
    _source = null;
    _contentCache.clear();
    _rawContents.clear();
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
        _rawContents
          ..clear()
          ..addAll(previousRaw);
        _contentInFlight.clear();
        _materializedContentIdentities
          ..clear()
          ..addAll(previousIdentities);
        // 重載途中規則改過（例如跑太久被停用）就重新讀，不放回舊的。
        _enabledRules = previousRulesRevision == _rulesRevision
            ? previousRules
            : null;
        _enabledRulesInFlight = null;
      }
    }
  }

  Future<ReaderContent> _loadContentUncached(
    int chapterIndex,
    int cacheGeneration,
  ) async {
    final chapter = chapterAt(chapterIndex);
    if (chapter == null) {
      throw const ReaderContentUnavailableException('章節內容載入失敗: 找不到章節');
    }
    final testLoader = contentLoader;
    if (testLoader != null) {
      final rawContent = await testLoader(chapterIndex, chapter);
      final raw = rawContent ?? chapter.content ?? '';
      final content = ReaderContent.fromRaw(
        chapterIndex: chapterIndex,
        title: chapter.title,
        rawText: raw,
      );
      if (cacheGeneration == _contentCacheGeneration) {
        _writeToContentCache(chapterIndex, content, raw: raw);
      }
      return content;
    }
    final loaded = await _loadViaContentPipeline(
      chapterIndex,
      chapter,
      cacheGeneration,
    );
    if (loaded != null) {
      if (cacheGeneration == _contentCacheGeneration) {
        _writeToContentCache(chapterIndex, loaded.content, raw: loaded.raw);
      }
      return loaded.content;
    }

    final raw = (chapter.content ?? '').trim();
    final content = ReaderContent.fromRaw(
      chapterIndex: chapterIndex,
      title: chapter.title,
      rawText: raw,
    );
    if (cacheGeneration == _contentCacheGeneration) {
      _writeToContentCache(chapterIndex, content, raw: raw);
    }
    return content;
  }

  void _writeToContentCache(
    int chapterIndex,
    ReaderContent content, {
    required String raw,
  }) {
    final previousIdentity = _materializedContentIdentities[chapterIndex];
    if (previousIdentity != null && previousIdentity != content.contentHash) {
      // Persistent acquisition can change outside the active Reader (for
      // example a downloader refresh). The content owner recognizes that
      // identity transition here; the text view must never infer it from layout.
      _contentGeneration += 1;
    }
    _materializedContentIdentities[chapterIndex] = content.contentHash;

    _contentCache.remove(chapterIndex);
    if (_contentCache.length >= _maxContentCacheSize) {
      _rawContents.remove(_contentCache.keys.first);
      _contentCache.remove(_contentCache.keys.first);
    }
    _contentCache[chapterIndex] = content;
    _rawContents[chapterIndex] = (contentHash: content.contentHash, raw: raw);
  }

  Future<List<ReplaceRule>> _ensureEnabledReplaceRules() {
    final dao = replaceDao;
    if (dao == null || !book.getUseReplaceRule()) {
      return Future<List<ReplaceRule>>.value(const <ReplaceRule>[]);
    }
    _ruleChanges ??= dao.watchChanges().listen((_) => _forgetEnabledRules());
    final cached = _enabledRules;
    if (cached != null) return Future<List<ReplaceRule>>.value(cached);
    final inFlight = _enabledRulesInFlight;
    if (inFlight != null) return inFlight;
    final cacheGeneration = _contentCacheGeneration;
    final rulesRevision = _rulesRevision;
    late final Future<List<ReplaceRule>> task;
    task = () async {
      try {
        final rules = await dao.getEnabledForBook(book.name, book.origin);
        if (cacheGeneration == _contentCacheGeneration &&
            rulesRevision == _rulesRevision) {
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
    if (book.origin.isEmpty || book.isLocal) return null;
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
      saveChapterMetadata: !book.isLocal,
    );
    if (fetched.isFailed) {
      throw ReaderContentUnavailableException(
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
      shouldStore: () => !_retired,
    );
  }

  Future<({ReaderContent content, String raw})?> _loadViaContentPipeline(
    int chapterIndex,
    BookChapter chapter,
    int cacheGeneration,
  ) async {
    final localExtension = localBookExtensionFromPath(book.bookUrl);
    if (book.isLocal &&
        book.bookUrl.startsWith('local://') &&
        localExtension.isNotEmpty &&
        !isSupportedLocalBookPath(book.bookUrl)) {
      throw const ReaderContentUnavailableException(
        '本地書格式不受支援，請使用 TXT 或 EPUB 檔案',
      );
    }
    final storage = _contentStorage(cacheGeneration);
    if (storage == null) return null;
    final prepared = await storage.read(
      chapterIndex: chapterIndex,
      chapter: chapter,
      saveChapterMetadata: !book.isLocal,
    );
    if (prepared.isFailed) {
      throw ReaderContentUnavailableException(
        (prepared.failureMessage ?? prepared.content).trim(),
      );
    }
    final enabledRules = await _ensureEnabledReplaceRules();
    try {
      final content = await _contentTransformer.process(
        chapterIndex: chapterIndex,
        book: book,
        chapter: chapter,
        rawContent: prepared.content,
        enabledRules: enabledRules,
        chineseConvertType: currentChineseConvert(),
        illustrationsDir: currentShowIllustrations()
            ? await BookIllustrationStorage.dirFor(book)
            : null,
        onRuleTimedOut: disableTimedOutRule,
      );
      return (content: content, raw: prepared.content);
    } on ReaderContentTransformException catch (error) {
      throw ReaderContentUnavailableException(error.message);
    }
  }

  /// 書源從舊網址搬家（[AppEventBus.sourceMoved]）：資料庫裡這本書、已下載
  /// 的正文與書本資料夾都已經改記新網址。照資料庫換上，之後的章照新書源抓、
  /// 照新網址讀已下載的正文；照舊網址讀的書源與替換規則作廢。
  Future<void> _followMove(SourceMovedEvent event) async {
    if (_disposed || event.fromUrl != _origin) return;
    _origin = event.toUrl;
    final stored = await bookDao.getByUrl(book.bookUrl);
    if (_disposed) return;
    if (stored != null) {
      book
        ..origin = stored.origin
        ..originName = stored.originName
        ..coverLocalPath = stored.coverLocalPath
        ..customCoverLocalPath = stored.customCoverLocalPath;
    } else {
      book.origin = event.toUrl;
    }
    _origin = book.origin;
    _source = null;
    _forgetEnabledRules();
    onOriginMoved?.call();
  }

  /// 規則表改過了：快取的規則清單作廢，下一章重新讀。
  void _forgetEnabledRules() {
    _rulesRevision += 1;
    _enabledRules = null;
    _enabledRulesInFlight = null;
  }

  /// 不再用了（閱讀器關掉）：停止跟著規則表的變動與書源搬家。
  void dispose() {
    _disposed = true;
    _retired = true;
    unawaited(_ruleChanges?.cancel());
    _ruleChanges = null;
    unawaited(_moves?.cancel());
    _moves = null;
  }

  bool _disposed = false;

  /// 套用正文時跑超過逾時的規則照 Legado 停用：開關關掉、存進資料庫，之後
  /// 的章不再帶它；這一章照其他規則處理完（[ReaderContentTransformWorker]）。
  /// 快取當下就作廢：重新讀規則排在停用之後，讀到的是停用後的。
  ///
  /// 停用一定要讓讀者看到提示（[onReplaceRuleDisabled]）。閱讀器已經關掉
  /// 時（還在預載的章才逾時）說不了，就先不停用：下次開書再逾時時，在畫面
  /// 上停用並提示。選字與替換規則面板找原文時規則逾時，也照這樣停用
  /// （和畫面上那次一樣，`ReaderContentTransformer.ruleStageParagraphs`）。
  void disableTimedOutRule(ReplaceRule rule) {
    if (_disposed) return;
    _forgetEnabledRules();
    final dao = replaceDao;
    if (dao != null) {
      unawaited(
        dao.updateEnabled(rule.id, false).catchError((
          Object error,
          StackTrace stackTrace,
        ) {
          AppLog.e('停用跑太久的替換規則失敗', error: error, stackTrace: stackTrace);
        }),
      );
    }
    onReplaceRuleDisabled?.call(rule);
  }

  bool _isValidChapterIndex(int chapterIndex) {
    return chapterIndex >= 0 && chapterIndex < _chapters.length;
  }

  int _normalizeChapterIndex(int chapterIndex) {
    if (_chapters.isEmpty) return chapterIndex < 0 ? 0 : chapterIndex;
    return chapterIndex.clamp(0, _chapters.length - 1).toInt();
  }
}
