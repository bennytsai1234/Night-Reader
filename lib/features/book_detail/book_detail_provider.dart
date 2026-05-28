import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:reader/core/services/app_log_service.dart';
import 'package:reader/core/database/dao/book_dao.dart';
import 'package:reader/core/database/dao/chapter_dao.dart';
import 'package:reader/core/database/dao/book_source_dao.dart';
import 'package:reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:reader/core/models/book.dart';
import 'package:reader/core/models/chapter.dart';
import 'package:reader/core/models/book_source.dart';
import 'package:reader/core/models/reader_chapter_content.dart';
import 'package:reader/core/models/search_book.dart';
import 'package:reader/core/services/book_source_service.dart';
import 'package:reader/core/services/book_cover_storage_service.dart';
import 'package:reader/core/services/download_service.dart';
import 'package:reader/core/services/reader_chapter_content_store.dart';
import 'package:reader/core/engine/app_event_bus.dart';
import 'package:reader/core/di/injection.dart';

class StorageDownloadQueueResult {
  const StorageDownloadQueueResult._({
    required this.queuedChapterCount,
    required this.message,
  });

  final int queuedChapterCount;
  final String message;

  factory StorageDownloadQueueResult.queued(int count) {
    return StorageDownloadQueueResult._(
      queuedChapterCount: count,
      message: '已加入背景下載佇列，共 $count 章',
    );
  }

  factory StorageDownloadQueueResult.blocked(String message) {
    return StorageDownloadQueueResult._(
      queuedChapterCount: 0,
      message: message,
    );
  }
}

class BookDetailOperationResult {
  const BookDetailOperationResult({
    required this.success,
    required this.message,
  });

  final bool success;
  final String message;

  factory BookDetailOperationResult.success(String message) {
    return BookDetailOperationResult(success: true, message: message);
  }

  factory BookDetailOperationResult.failure(String message) {
    return BookDetailOperationResult(success: false, message: message);
  }
}

class BookDetailUpdateResult {
  const BookDetailUpdateResult({
    required this.success,
    required this.newChapterCount,
    required this.totalChapterCount,
    required this.message,
  });

  final bool success;
  final int newChapterCount;
  final int totalChapterCount;
  final String message;

  bool get hasUpdate => newChapterCount > 0;
}

class BookDetailCacheStatus {
  const BookDetailCacheStatus({
    required this.storedChapterCount,
    required this.totalChapterCount,
    required this.contentBytes,
    required this.coverBytes,
    required this.latestContentUpdatedAt,
  });

  final int storedChapterCount;
  final int totalChapterCount;
  final int contentBytes;
  final int coverBytes;
  final int latestContentUpdatedAt;

  int get totalBytes => contentBytes + coverBytes;
  int get missingChapterCount =>
      math.max(0, totalChapterCount - storedChapterCount);
  bool get hasContentCache => storedChapterCount > 0 || contentBytes > 0;
  bool get hasCoverCache => coverBytes > 0;
  bool get hasAnyCache => hasContentCache || hasCoverCache;

  static const empty = BookDetailCacheStatus(
    storedChapterCount: 0,
    totalChapterCount: 0,
    contentBytes: 0,
    coverBytes: 0,
    latestContentUpdatedAt: 0,
  );
}

enum BookDetailCacheClearTarget { content, cover, all }

class BookDetailProvider extends ChangeNotifier {
  final BookDao _bookDao;
  final ChapterDao _chapterDao;
  final BookSourceDao _sourceDao;
  final ReaderChapterContentDao? _chapterContentDao;
  final BookSourceService _service;
  final BookCoverStorageService _coverStorage;
  DownloadService? _downloadService;

  late Book _book;
  List<BookChapter> _allChapters = [];
  List<BookChapter> _displayChapters = [];
  bool _isLoading = true;
  bool _isInBookshelf = false;
  BookSource? _currentSource;
  BookSource? get currentSource => _currentSource;
  String? _sourceIssueMessage;
  String? get sourceIssueMessage => _sourceIssueMessage;
  BookDetailCacheStatus _cacheStatus = BookDetailCacheStatus.empty;
  bool _isCacheStatusLoading = false;
  bool _isCheckingUpdate = false;

  Book get book => _book;
  List<BookChapter> get filteredChapters => _displayChapters;
  List<BookChapter> get allChapters => List.unmodifiable(_allChapters);
  int get totalChapterCount => _allChapters.length;
  bool get isLoading => _isLoading;
  bool get isInBookshelf => _isInBookshelf;
  BookDetailCacheStatus get cacheStatus => _cacheStatus;
  bool get isCacheStatusLoading => _isCacheStatusLoading;
  bool get isCheckingUpdate => _isCheckingUpdate;
  bool get supportsBackgroundDownload => _book.origin != 'local';
  DownloadService get _resolvedDownloadService =>
      _downloadService ??= DownloadService();
  String get sourceStatusLabel {
    if (_book.isLocal) return '本地';
    final source = _currentSource;
    if (source == null) return '找不到書源';
    if (!source.enabled) return '停用';
    return source.runtimeHealth.label;
  }

  String get sourceStatusDescription {
    if (_book.isLocal) return '本地書籍不依賴線上書源';
    final source = _currentSource;
    if (source == null) return '目前找不到這本書對應的書源';
    if (!source.enabled) return '書源已停用';
    return source.runtimeHealth.description;
  }

  bool get sourceStatusIsHealthy =>
      _book.isLocal ||
      (_currentSource != null &&
          _currentSource!.enabled &&
          _currentSource!.runtimeHealth.category ==
              SourceHealthCategory.healthy);

  String _searchQuery = '';
  bool _isReversed = false;
  bool _disposed = false;
  bool get isReversed => _isReversed;

  Timer? _debounce;

  BookDetailProvider(
    AggregatedSearchBook searchBook, {
    BookDao? bookDao,
    ChapterDao? chapterDao,
    BookSourceDao? sourceDao,
    ReaderChapterContentDao? chapterContentDao,
    BookSourceService? service,
    BookCoverStorageService? coverStorage,
    DownloadService? downloadService,
  }) : _bookDao = bookDao ?? getIt<BookDao>(),
       _chapterDao = chapterDao ?? getIt<ChapterDao>(),
       _sourceDao = sourceDao ?? getIt<BookSourceDao>(),
       _chapterContentDao =
           chapterContentDao ??
           (getIt.isRegistered<ReaderChapterContentDao>()
               ? getIt<ReaderChapterContentDao>()
               : null),
       _service = service ?? BookSourceService(),
       _coverStorage = coverStorage ?? BookCoverStorageService(),
       _downloadService = downloadService {
    _book =
        searchBook.book is Book
            ? searchBook.book as Book
            : Book(
              bookUrl: searchBook.book.bookUrl,
              name: searchBook.book.name,
              author: searchBook.book.author ?? '未知',
              coverUrl: searchBook.book.coverUrl,
              intro: searchBook.book.intro,
              origin: searchBook.book.origin,
              originName: searchBook.book.originName ?? '發現',
              type: searchBook.book.type,
            );
    _init();
  }

  Future<void> _init() async {
    final existing = await _bookDao.getByUrl(_book.bookUrl);
    if (existing != null) {
      _book = existing;
      _isInBookshelf = existing.isInBookshelf;
    } else {
      _book.isInBookshelf = false;
      await _bookDao.upsert(_book);
    }
    await _loadSource();
    await _loadBookInfo();
    await _loadChapters();
    unawaited(_storeDisplayCover());
    _isLoading = false;
    notifyListeners();
  }

  Future<void> _loadSource() async {
    _currentSource = await _sourceDao.getByUrl(_book.origin);
    final health = _currentSource?.runtimeHealth;
    if (health != null &&
        health.category != SourceHealthCategory.healthy &&
        !health.allowsReading) {
      _sourceIssueMessage = health.description;
    } else {
      _sourceIssueMessage = null;
    }
  }

  /// 載入書籍詳情 (對標 Android BookInfoViewModel.loadBookInfo)
  /// 從書源獲取完整書籍資訊，包含 tocUrl、簡介、封面等
  Future<void> _loadBookInfo() async {
    if (_currentSource == null) return;
    if (!_currentSource!.isReadingEnabledByRuntime) {
      return;
    }
    try {
      final wasInBookshelf = _book.isInBookshelf;
      final coverLocalPath = _book.coverLocalPath;
      final customCoverUrl = _book.customCoverUrl;
      final customCoverLocalPath = _book.customCoverLocalPath;
      final updatedBook = await _service.getBookInfo(_currentSource!, _book);
      updatedBook.isInBookshelf = wasInBookshelf;
      updatedBook.coverLocalPath = coverLocalPath;
      updatedBook.customCoverUrl = customCoverUrl;
      updatedBook.customCoverLocalPath = customCoverLocalPath;
      _book = updatedBook;
      await _bookDao.upsert(_book);
    } catch (e) {
      AppLog.e('加載書籍詳情失敗: $e', error: e);
      // 即使加載詳情失敗，仍嘗試用已有資訊載入目錄
      // 若 tocUrl 為空，以 bookUrl 作為備用
      if (_book.tocUrl.isEmpty) {
        _book.tocUrl = _book.bookUrl;
      }
      await _bookDao.upsert(_book);
    }
  }

  Future<void> _loadChapters() async {
    _allChapters = await _chapterDao.getByBook(_book.bookUrl);

    if (_allChapters.isEmpty && _currentSource != null) {
      if (!_currentSource!.isReadingEnabledByRuntime) {
        _applyFilter();
        return;
      }
      try {
        _allChapters = await _service.getChapterList(_currentSource!, _book);
        await _chapterDao.insertChapters(_allChapters);
      } catch (e) {
        _sourceIssueMessage = '目前來源目錄載入失敗，建議換源後再試';
        AppLog.e('加載目錄失敗: $e', error: e);
      }
    }
    _applyFilter();
  }

  Future<StorageDownloadQueueResult> queueDownloadAll() async {
    return _queueStorageDownload(
      resolveChapters: (_) => List<BookChapter>.from(_allChapters),
      emptyMessage: '目前沒有可下載的章節',
    );
  }

  Future<StorageDownloadQueueResult> queueDownloadFromCurrent() async {
    return _queueStorageDownload(
      resolveChapters: (_) {
        final startIndex = book.chapterIndex.clamp(0, _allChapters.length);
        return _allChapters
            .where((chapter) => chapter.index >= startIndex)
            .toList();
      },
      emptyMessage: '目前進度之後沒有可下載的章節',
    );
  }

  Future<StorageDownloadQueueResult> queueDownloadNext(int count) async {
    if (count <= 0) {
      return StorageDownloadQueueResult.blocked('下載章節數必須大於 0');
    }
    return _queueStorageDownload(
      resolveChapters: (_) {
        final startIndex = book.chapterIndex.clamp(0, _allChapters.length);
        return _allChapters
            .where((chapter) => chapter.index >= startIndex)
            .take(count)
            .toList();
      },
      emptyMessage: '目前進度之後沒有可下載的章節',
    );
  }

  Future<StorageDownloadQueueResult> queueDownloadRange(
    int startIndex,
    int endIndex,
  ) async {
    return _queueStorageDownload(
      resolveChapters: (_) {
        if (_allChapters.isEmpty) return <BookChapter>[];
        final start = startIndex.clamp(0, _allChapters.length - 1);
        final end = endIndex.clamp(0, _allChapters.length - 1);
        if (end < start) return <BookChapter>[];
        return _allChapters
            .where((chapter) => chapter.index >= start && chapter.index <= end)
            .toList();
      },
      emptyMessage: '指定範圍沒有可下載的章節',
    );
  }

  Future<StorageDownloadQueueResult> queueDownloadMissing() async {
    return _queueStorageDownload(
      resolveChapters:
          (storedIndices) =>
              _allChapters
                  .where((chapter) => !storedIndices.contains(chapter.index))
                  .toList(),
      emptyMessage: '目前沒有新的章節需要下載',
    );
  }

  Future<StorageDownloadQueueResult> _queueStorageDownload({
    required List<BookChapter> Function(Set<int> storedIndices) resolveChapters,
    required String emptyMessage,
  }) async {
    final blockedReason = await _prepareStorageDownloadQueue();
    if (blockedReason != null) {
      return StorageDownloadQueueResult.blocked(blockedReason);
    }

    final storedIndices = await _storedChapterIndices();
    final chapters = resolveChapters(storedIndices);
    if (chapters.isEmpty) {
      return StorageDownloadQueueResult.blocked(emptyMessage);
    }

    await _resolvedDownloadService.addDownloadTask(_book, chapters);
    return StorageDownloadQueueResult.queued(chapters.length);
  }

  Future<String?> _prepareStorageDownloadQueue() async {
    if (!supportsBackgroundDownload) {
      return '這本書已經在裝置內，不需要背景下載。';
    }

    if (_currentSource == null) {
      await _loadSource();
    }
    final source = _currentSource;
    if (source == null) {
      return '目前找不到書源，請先換源後再試。';
    }
    if (!source.isReadingEnabledByRuntime) {
      return _sourceIssueMessage ?? '目前來源無法提供正文，請先換源後再試。';
    }

    if (_allChapters.isEmpty) {
      await _loadChapters();
    }
    if (_allChapters.isEmpty) {
      return _sourceIssueMessage ?? '目前沒有可下載的章節。';
    }

    await _bookDao.upsert(_book);
    await _saveChapterMetadataIfPossible();

    return null;
  }

  void setSearchQuery(String q) {
    _searchQuery = q;
    if (_debounce?.isActive ?? false) _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _applyFilter();
    });
  }

  void toggleSort() {
    _isReversed = !_isReversed;
    _applyFilter();
  }

  void resetTocViewForCurrentChapter() {
    _searchQuery = '';
    _isReversed = false;
    _debounce?.cancel();
    _applyFilter();
  }

  int displayIndexForChapter(int chapterIndex) {
    return _displayChapters.indexWhere(
      (chapter) => chapter.index == chapterIndex,
    );
  }

  void _applyFilter() {
    var list = _allChapters;
    if (_searchQuery.isNotEmpty) {
      list =
          list
              .where(
                (c) =>
                    c.title.toLowerCase().contains(_searchQuery.toLowerCase()),
              )
              .toList();
    }
    _displayChapters = _isReversed ? list.reversed.toList() : List.from(list);
    notifyListeners();
  }

  /// 執行換源：來源切換建立為另一本書，不覆蓋/刪除原書 storage。
  Future<BookDetailOperationResult> changeSource(SearchBook newSource) async {
    _isLoading = true;
    notifyListeners();
    try {
      final oldBook = _book.copyWith();
      final candidate = newSource.toBook();
      final source = await _sourceDao.getByUrl(candidate.origin);
      if (source == null) {
        throw StateError('找不到對應書源');
      }
      _currentSource = source;
      final hydratedBook = await _service.getBookInfo(source, candidate);
      final nextBook = oldBook.migrateTo(
        hydratedBook.copyWith(isInBookshelf: oldBook.isInBookshelf),
        const <BookChapter>[],
      );
      _book = nextBook;
      await _loadSource();
      await _loadBookInfo();
      _allChapters = [];
      if (_currentSource != null) {
        _allChapters = await _service.getChapterList(_currentSource!, _book);
      }
      _book = oldBook.migrateTo(_book, _allChapters);
      _isInBookshelf = _book.isInBookshelf;
      await _chapterDao.deleteByBook(_book.bookUrl);
      await _bookDao.upsert(_book);
      await _chapterDao.insertChapters(_allChapters);
      await _refreshCacheStatus(notify: false);
      unawaited(_storeDisplayCover());
      _applyFilter();
      AppEventBus().fire(AppEventBus.upBookshelf);
      return BookDetailOperationResult.success('已切換到 ${_book.originName}');
    } catch (e) {
      AppLog.e('換源失敗: $e', error: e);
      return BookDetailOperationResult.failure('換源失敗: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> toggleInBookshelf() async {
    await setInBookshelf(!_isInBookshelf);
  }

  Future<BookDetailOperationResult> setInBookshelf(bool value) async {
    if (_isInBookshelf == value) {
      return BookDetailOperationResult.success(value ? '已在書架中' : '已移出書架');
    }

    final previous = _isInBookshelf;
    _isInBookshelf = value;
    _book.isInBookshelf = value;
    notifyListeners();

    if (_isInBookshelf) {
      if (_book.syncTime == 0) {
        _book.syncTime = DateTime.now().millisecondsSinceEpoch;
      }
      try {
        if (_allChapters.isEmpty) {
          await _loadChapters();
        }
        _initializeProgressForBookshelf();
        await _bookDao.upsert(_book);
        await _saveChapterMetadataIfPossible();
      } catch (e) {
        AppLog.e('加入書架失敗: $e', error: e);
        _isInBookshelf = previous;
        _book.isInBookshelf = previous;
        notifyListeners();
        return BookDetailOperationResult.failure('加入書架失敗: $e');
      }
    } else {
      await _bookDao.upsert(_book);
    }

    AppEventBus().fire(AppEventBus.upBookshelf);
    notifyListeners();
    return BookDetailOperationResult.success(value ? '已加入書架' : '已移出書架');
  }

  void _initializeProgressForBookshelf() {
    if (_allChapters.isEmpty) return;
    if (_book.durChapterTitle != null && _book.durChapterTitle!.isNotEmpty) {
      return;
    }
    if (_book.chapterIndex != 0 || _book.charOffset != 0) return;

    final firstChapter = _allChapters.first;
    _book.chapterIndex = firstChapter.index;
    _book.charOffset = 0;
    _book.visualOffsetPx = 0.0;
    _book.readerAnchorJson = null;
    _book.durChapterTitle = firstChapter.title;
  }

  Future<void> updateBookInfo(
    String name,
    String author,
    String intro,
    String coverUrl, {
    String? kind,
    String? customTag,
    String? originName,
    String? tocUrl,
  }) async {
    _book.name = name.trim();
    _book.author = author.trim();
    _book.intro = intro.trim();
    _book.customIntro = intro.trim();
    _book.kind = kind?.trim();
    _book.customTag = customTag?.trim();
    if (originName != null && originName.trim().isNotEmpty) {
      _book.originName = originName.trim();
    }
    if (tocUrl != null) {
      _book.tocUrl = tocUrl.trim();
    }
    _book.coverUrl = coverUrl.trim();
    _book.coverLocalPath = null;
    await _bookDao.upsert(_book);
    unawaited(_storeDisplayCover());
    notifyListeners();
  }

  Future<void> updateCover(String url) async {
    _book.customCoverUrl = url;
    _book.customCoverLocalPath = null;
    await _storeDisplayCover();
    await _bookDao.upsert(_book);
    notifyListeners();
  }

  Future<BookDetailOperationResult> clearStoredContent() async {
    await _clearStoredContent();
    await _refreshCacheStatus();
    return BookDetailOperationResult.success('已移除本書正文儲存');
  }

  Future<BookDetailOperationResult> clearBookCache(
    BookDetailCacheClearTarget target,
  ) async {
    try {
      if (target == BookDetailCacheClearTarget.content ||
          target == BookDetailCacheClearTarget.all) {
        await _clearStoredContent();
      }
      if (target == BookDetailCacheClearTarget.cover ||
          target == BookDetailCacheClearTarget.all) {
        await _coverStorage.deleteBookAssets(_book);
        await _bookDao.upsert(_book);
      }
      await _refreshCacheStatus();
      notifyListeners();
      final message = switch (target) {
        BookDetailCacheClearTarget.content => '已清除本書正文快取',
        BookDetailCacheClearTarget.cover => '已清除本書封面快取',
        BookDetailCacheClearTarget.all => '已清除本書全部快取',
      };
      return BookDetailOperationResult.success(message);
    } catch (e) {
      AppLog.e('清除本書快取失敗: $e', error: e);
      return BookDetailOperationResult.failure('清除快取失敗: $e');
    }
  }

  Future<void> refreshCacheStatus() => _refreshCacheStatus();

  Future<BookDetailUpdateResult> checkForUpdates() async {
    if (_book.isLocal) {
      return const BookDetailUpdateResult(
        success: false,
        newChapterCount: 0,
        totalChapterCount: 0,
        message: '本地書不需要檢查線上更新',
      );
    }

    _isCheckingUpdate = true;
    notifyListeners();
    final checkedAt = DateTime.now().millisecondsSinceEpoch;
    try {
      if (_currentSource == null) {
        await _loadSource();
      }
      final source = _currentSource;
      if (source == null || !source.isReadingEnabledByRuntime) {
        throw StateError(_sourceIssueMessage ?? '找不到可閱讀書源');
      }

      final oldBook = _book.copyWith();
      final oldTotal =
          _allChapters.isNotEmpty
              ? _allChapters.length
              : math.max(0, oldBook.totalChapterNum);
      final info = await _service.getBookInfo(source, oldBook);
      final chapters = await _service.getChapterList(source, info);
      for (var i = 0; i < chapters.length; i++) {
        chapters[i].index = i;
        chapters[i].bookUrl = oldBook.bookUrl;
      }

      final newCount =
          chapters.length > oldTotal ? chapters.length - oldTotal : 0;
      info.bookUrl = oldBook.bookUrl;
      info.origin = oldBook.origin;
      info.originName = oldBook.originName;
      if (info.tocUrl.isEmpty) info.tocUrl = oldBook.tocUrl;
      info.isInBookshelf = oldBook.isInBookshelf;
      info.group = oldBook.group;
      info.order = oldBook.order;
      info.syncTime = oldBook.syncTime;
      info.chapterIndex = oldBook.chapterIndex;
      info.charOffset = oldBook.charOffset;
      info.visualOffsetPx = oldBook.visualOffsetPx;
      info.durChapterTitle = oldBook.durChapterTitle;
      info.durChapterTime = oldBook.durChapterTime;
      info.readerAnchorJson = oldBook.readerAnchorJson;
      info.canUpdate = oldBook.canUpdate;
      info.customCoverUrl = oldBook.customCoverUrl;
      info.customCoverLocalPath = oldBook.customCoverLocalPath;
      info.customIntro = oldBook.customIntro;
      info.customTag = oldBook.customTag;
      info.readConfig = oldBook.readConfig;
      info.lastCheckTime = checkedAt;
      info.lastCheckCount = newCount;
      info.totalChapterNum = chapters.length;
      if (chapters.isNotEmpty) {
        info.latestChapterTitle = chapters.last.title;
        if (newCount > 0) {
          info.latestChapterTime = checkedAt;
        }
      }

      _book = info;
      _isInBookshelf = info.isInBookshelf;
      _allChapters = chapters;
      await _chapterDao.deleteByBook(_book.bookUrl);
      if (chapters.isNotEmpty) {
        await _chapterDao.insertChapters(chapters);
      }
      await _bookDao.upsert(_book);
      await _refreshCacheStatus(notify: false);
      _applyFilter();
      AppEventBus().fire(AppEventBus.upBookshelf);
      return BookDetailUpdateResult(
        success: true,
        newChapterCount: newCount,
        totalChapterCount: chapters.length,
        message:
            newCount > 0 ? '發現 $newCount 個新章節' : '已是最新，總共 ${chapters.length} 章',
      );
    } catch (e) {
      AppLog.e('檢查書籍更新失敗: $e', error: e);
      _book.lastCheckTime = checkedAt;
      await _bookDao.upsert(_book);
      return BookDetailUpdateResult(
        success: false,
        newChapterCount: 0,
        totalChapterCount: _allChapters.length,
        message: '檢查更新失敗: $e',
      );
    } finally {
      _isCheckingUpdate = false;
      notifyListeners();
    }
  }

  Future<void> _saveChapterMetadataIfPossible() {
    if (_allChapters.isEmpty) return Future<void>.value();
    final chapterContentDao = _chapterContentDao;
    if (chapterContentDao == null) {
      return _chapterDao.insertChapters(_allChapters);
    }
    return ReaderChapterContentStore(
      chapterDao: _chapterDao,
      contentDao: chapterContentDao,
    ).saveChapterMetadata(_allChapters);
  }

  Future<Set<int>> _storedChapterIndices() async {
    final chapterContentDao = _chapterContentDao;
    if (chapterContentDao == null) return <int>{};
    return ReaderChapterContentStore(
      chapterDao: _chapterDao,
      contentDao: chapterContentDao,
    ).storedChapterIndices(book: _book);
  }

  Future<void> _clearStoredContent() async {
    final chapterContentDao = _chapterContentDao;
    if (chapterContentDao == null) return;
    await ReaderChapterContentStore(
      chapterDao: _chapterDao,
      contentDao: chapterContentDao,
    ).deleteStoredContentForBook(book: _book);
  }

  Future<void> _refreshCacheStatus({bool notify = true}) async {
    _isCacheStatusLoading = true;
    if (notify) notifyListeners();
    try {
      final chapterContentDao = _chapterContentDao;
      final entries =
          chapterContentDao == null
              ? const <ReaderChapterContentEntry>[]
              : await chapterContentDao.getEntriesByBookUrls(<String>[
                _book.bookUrl,
              ]);
      final storedIndices = <int>{};
      var contentBytes = 0;
      var latestUpdatedAt = 0;
      for (final entry in entries) {
        if (entry.origin != _book.origin ||
            !entry.isReady ||
            !entry.hasDisplayContent) {
          continue;
        }
        storedIndices.add(entry.chapterIndex);
        final content = entry.content;
        if (content != null && content.isNotEmpty) {
          contentBytes += utf8.encode(content).length;
        }
        latestUpdatedAt = math.max(latestUpdatedAt, entry.updatedAt);
      }

      final coverBytes = await _coverStorage.getBookAssetSize(_book);
      _cacheStatus = BookDetailCacheStatus(
        storedChapterCount: storedIndices.length,
        totalChapterCount: _allChapters.length,
        contentBytes: contentBytes,
        coverBytes: coverBytes,
        latestContentUpdatedAt: latestUpdatedAt,
      );
    } finally {
      _isCacheStatusLoading = false;
      if (notify && !_disposed) notifyListeners();
    }
  }

  Future<void> _storeDisplayCover() async {
    await _coverStorage.ensureDisplayCoverStored(_book);
    await _bookDao.upsert(_book);
    if (!_isLoading && !_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    super.dispose();
  }
}
