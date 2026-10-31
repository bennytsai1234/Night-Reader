import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/core/exception/user_error.dart';
import 'package:flutter/foundation.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/reader_chapter_content.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/services/book_source_service.dart';
import 'package:night_reader/core/services/book_cover_storage_service.dart';
import 'package:night_reader/core/services/book_storage_service.dart';
import 'package:night_reader/core/services/book_update_service.dart';
import 'package:night_reader/core/storage/reader_layout_cache.dart';
import 'package:night_reader/core/services/download_service.dart';
import 'package:night_reader/core/services/reader_chapter_content_store.dart';
import 'package:night_reader/core/services/source_switch_service.dart';
import 'package:night_reader/core/engine/app_event_bus.dart';
import 'package:night_reader/core/di/injection.dart';

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

enum BookDetailWorldState { initializing, ready, unavailable }

class BookDetailProvider extends ChangeNotifier {
  static const String _bookInfoDegradationMessage = '書籍資訊更新失敗，目前顯示已儲存內容';

  final BookDao _bookDao;
  final ChapterDao _chapterDao;
  final BookSourceDao _sourceDao;
  final ReaderChapterContentDao? _chapterContentDao;
  final BookSourceService _service;
  final BookCoverStorageService _coverStorage;
  late final SourceSwitchService _sourceSwitchService;
  late final BookStorageService _bookStorageService;
  late final BookUpdateService _updates;
  DownloadService? _downloadService;

  late Book _book;
  List<BookChapter> _allChapters = [];
  List<BookChapter> _displayChapters = [];
  BookDetailWorldState _worldState = BookDetailWorldState.initializing;
  String? _loadErrorMessage;
  BookSource? _currentSource;
  BookSource? get currentSource => _currentSource;
  String? _sourceIssueMessage;
  String? get sourceIssueMessage => _sourceIssueMessage;

  /// 目錄要登入才讀得到，書源也有登入：[sourceIssueMessage] 那一列點了去
  /// 登入（ADR 0038）。
  bool _loginRequired = false;
  bool get loginRequired => _loginRequired;
  BookDetailCacheStatus _cacheStatus = BookDetailCacheStatus.empty;
  bool _isCacheStatusLoading = false;
  bool _isCheckingUpdate = false;
  bool _isChangingSource = false;

  Book get book => _book;

  /// 這一輪載入的骨架照哪本書排（DESIGN「書籍詳情」：照進頁時手上的書）。
  /// 每次開始載入（[_init]）時記下一份，載入中與這一輪的換場播完前都照
  /// 它：資料到了只換掉骨架底下的內容，骨架不先變成新資料的形狀。
  Book get skeletonBook => _skeletonBook;
  late Book _skeletonBook;
  List<BookChapter> get filteredChapters => _displayChapters;
  List<BookChapter> get allChapters => List.unmodifiable(_allChapters);
  int get totalChapterCount => _allChapters.length;
  BookDetailWorldState get worldState => _worldState;
  bool get isLoading => _worldState == BookDetailWorldState.initializing;
  bool get hasReadyWorld => _worldState == BookDetailWorldState.ready;
  String? get loadErrorMessage => _loadErrorMessage;
  bool get isInBookshelf => _book.isInBookshelf;
  BookDetailCacheStatus get cacheStatus => _cacheStatus;
  bool get isCacheStatusLoading => _isCacheStatusLoading;
  bool get isCheckingUpdate => _isCheckingUpdate;
  bool get isChangingSource => _isChangingSource;
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
  String get tocSearchQuery => _searchQuery;
  bool get hasActiveTocSearch => _searchQuery.isNotEmpty;

  Timer? _debounce;

  BookDetailProvider(
    AggregatedSearchBook searchBook, {
    required Future<void> entrance,
    BookDao? bookDao,
    ChapterDao? chapterDao,
    BookSourceDao? sourceDao,
    ReaderChapterContentDao? chapterContentDao,
    BookSourceService? service,
    SourceSwitchService? sourceSwitchService,
    BookCoverStorageService? coverStorage,
    this._downloadService,
    BookStorageService? bookStorageService,
    BookUpdateService? updates,
  }) : _bookDao = bookDao ?? getIt<BookDao>(),
       _chapterDao = chapterDao ?? getIt<ChapterDao>(),
       _sourceDao = sourceDao ?? getIt<BookSourceDao>(),
       _chapterContentDao =
           chapterContentDao ??
           (getIt.isRegistered<ReaderChapterContentDao>()
               ? getIt<ReaderChapterContentDao>()
               : null),
       _service = service ?? BookSourceService(),
       _coverStorage = coverStorage ?? BookCoverStorageService() {
    _sourceSwitchService =
        sourceSwitchService ??
        SourceSwitchService(
          service: _service,
          sourceDao: _sourceDao,
          operationQuiescer: (oldBook) =>
              _resolvedDownloadService.quiesceForSourceSwitch(oldBook),
          assetRetirer: _coverStorage.handoffSourceSwitchAssets,
        );
    _updates =
        updates ??
        BookUpdateService(
          keepDownloaded: (bookUrl, {hasNewChapters = false}) =>
              _resolvedDownloadService.keepShelfBookDownloaded(
                bookUrl,
                hasNewChapters: hasNewChapters,
              ),
          bookDao: _bookDao,
        );
    _bookStorageService =
        bookStorageService ??
        BookStorageService(
          bookDao: _bookDao,
          chapterDao: _chapterDao,
          contentDao: _chapterContentDao,
          downloadService: _downloadService,
          coverStorage: _coverStorage,
        );
    _book = searchBook.book is Book
        ? searchBook.book as Book
        : Book(
            bookUrl: searchBook.book.bookUrl,
            name: searchBook.book.name,
            author: searchBook.book.author ?? '未知',
            coverUrl: searchBook.book.coverUrl,
            intro: searchBook.book.intro,
            kind: searchBook.book.kind,
            wordCount: searchBook.book.wordCount,
            latestChapterTitle: searchBook.book.latestChapterTitle,
            origin: searchBook.book.origin,
            originName: searchBook.book.originName ?? '發現',
            type: searchBook.book.type,
          );
    _skeletonBook = _book.copyWith();
    _switchSub = AppEventBus()
        .onName(AppEventBus.bookSwitched)
        .listen((event) => _followSwitch(event.data as BookSwitchedEvent));
    // 進場動畫播完才讀資料庫、向書源抓資料（ADR 0018）；這之前照傳進來
    // 的書畫。
    unawaited(entrance.then((_) => _init()));
  }

  StreamSubscription<AppEvent>? _switchSub;

  /// 從這裡開的閱讀器換了源：書的網址可能換了，舊的那筆已刪掉；記下新的，
  /// 回到這頁時（[reloadAfterReading]）改顯示它。這頁自己換源時已經換好。
  String? _switchedBookUrl;

  void _followSwitch(BookSwitchedEvent event) {
    if (_isChangingSource) return;
    if (event.fromBookUrl != (_switchedBookUrl ?? _book.bookUrl)) return;
    _switchedBookUrl = event.toBookUrl;
  }

  /// 從閱讀器回到這頁：閱讀器把進度、加入書架與換源都寫進資料庫，這裡照
  /// 資料庫裡的這本書重新顯示。閱讀器沒加入書架就退出時，書與目錄已經刪
  /// 掉，照舊顯示手上的書（不在書架上）。
  Future<void> reloadAfterReading() async {
    if (_disposed || !hasReadyWorld) return;
    final switchedUrl = _switchedBookUrl;
    _switchedBookUrl = null;
    final stored = await _bookDao.getByUrl(switchedUrl ?? _book.bookUrl);
    if (_disposed) return;
    if (stored == null) {
      _book.isInBookshelf = false;
      notifyListeners();
      return;
    }
    final switched =
        stored.bookUrl != _book.bookUrl || stored.origin != _book.origin;
    _book = stored;
    if (switched) await _loadSource();
    final chapters = await _chapterDao.getByBook(_book.bookUrl);
    if (_disposed) return;
    if (chapters.isNotEmpty || switched) _allChapters = chapters;
    // 和這頁自己換源一樣，存下新書源的封面。
    if (switched) unawaited(_storeDisplayCover());
    _applyFilter();
  }

  Future<void> retryInitialization() => _init();

  Future<void> _init() async {
    if (_disposed) return;
    // 新的一輪載入（重試）：骨架換成照目前手上的書排。第一輪進頁時已經是這個
    // 樣子，不再通知：原本進場一播完就整頁連同骨架重建一次，畫面沒有任何
    // 改變（ADR 0018）。
    if (_worldState != BookDetailWorldState.initializing ||
        _loadErrorMessage != null) {
      _skeletonBook = _book.copyWith();
      _worldState = BookDetailWorldState.initializing;
      _loadErrorMessage = null;
      notifyListeners();
    }
    try {
      final existing = await _bookDao.getByUrl(_book.bookUrl);
      if (existing != null) {
        _book = existing;
      } else {
        _book.isInBookshelf = false;
        await _bookDao.upsert(_book);
      }
      await _loadSource();
      // 書架上的書目錄已經存在手機裡，書籍資訊由書架的檢查更新重抓；這裡
      // 不再向書源要，網路差時才不會整頁停在骨架、什麼都不能按。
      final storedChapters = await _chapterDao.getByBook(_book.bookUrl);
      if (_book.isInBookshelf && storedChapters.isNotEmpty) {
        _allChapters = storedChapters;
        _announceCover();
        _applyFilter();
      } else {
        await _loadBookInfo();
        // 封面一拿到就告訴搜尋頁，不等目錄。
        _announceCover();
        await _loadChapters();
      }
      _worldState = BookDetailWorldState.ready;
      unawaited(_storeDisplayCover());
    } catch (error, stackTrace) {
      AppLog.e('載入書籍詳情失敗: $error', error: error, stackTrace: stackTrace);
      _loadErrorMessage = '書籍詳情載入失敗，請重試';
      _worldState = BookDetailWorldState.unavailable;
    } finally {
      if (!_disposed) notifyListeners();
    }
  }

  /// 從書源編輯或除錯頁回來時重讀這本書的書源：那邊存的規則、啟用與健康
  /// 狀態只寫進資料庫，詳情手上的還是舊的；不重讀的話，再進一次編輯頁會
  /// 帶入舊規則，存檔就蓋掉上一次的修改。
  Future<void> reloadSource() async {
    if (_disposed) return;
    // 編輯頁可能改了書源網址：資料庫裡的書已經改記新網址，照它找書源。
    final stored = await _bookDao.getByUrl(_book.bookUrl);
    if (_disposed) return;
    if (stored != null) {
      _book
        ..origin = stored.origin
        ..originName = stored.originName;
    }
    await _loadSource();
    if (!_disposed) notifyListeners();
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
      _clearBookInfoDegradation();
      await _bookDao.upsert(_book);
    } catch (e) {
      AppLog.e('加載書籍詳情失敗: $e', error: e);
      _sourceIssueMessage ??= _bookInfoDegradationMessage;
      if (_book.tocUrl.isEmpty) {
        _book.tocUrl = _book.bookUrl;
      }
      await _bookDao.upsert(_book);
    }
  }

  void _clearBookInfoDegradation() {
    if (_sourceIssueMessage == _bookInfoDegradationMessage) {
      _sourceIssueMessage = null;
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
        _loginRequired = false;
      } catch (e) {
        _loginRequired =
            _currentSource!.hasLogin &&
            (e is LoginCheckException || LoginCheckException.describes('$e'));
        _sourceIssueMessage = _loginRequired
            ? '目錄需要登入後閱讀'
            : '目前來源目錄載入失敗，建議換源後再試';
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
      fromFirstResolved: true,
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
      fromFirstResolved: true,
      toLastResolved: true,
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
      fromFirstResolved: true,
      toLastResolved: true,
    );
  }

  Future<StorageDownloadQueueResult> queueDownloadMissing() async {
    return _queueStorageDownload(
      resolveChapters: (storedUrls) =>
          chaptersMissingContent(_allChapters, storedUrls),
      emptyMessage: '目前沒有新的章節需要下載',
    );
  }

  /// [fromFirstResolved]／[toLastResolved]：任務的範圍從解析出的第一章開始
  /// ／到最後一章為止；否則從目錄第一章／到開跑時目錄的最後一章。兩端都
  /// 不固定的是整本任務（「下載全部」「下載缺少的」），進度算整本。
  Future<StorageDownloadQueueResult> _queueStorageDownload({
    required List<BookChapter> Function(Set<String> storedUrls) resolveChapters,
    required String emptyMessage,
    bool fromFirstResolved = false,
    bool toLastResolved = false,
  }) async {
    final blockedReason = await _prepareStorageDownloadQueue();
    if (blockedReason != null) {
      return StorageDownloadQueueResult.blocked(blockedReason);
    }

    final storedUrls = await _storedChapterUrls();
    final chapters = resolveChapters(storedUrls);
    if (chapters.isEmpty) {
      return StorageDownloadQueueResult.blocked(emptyMessage);
    }

    await _resolvedDownloadService.addDownloadTask(
      _book,
      fromFirstResolved || toLastResolved ? chapters : _allChapters,
      from: fromFirstResolved ? chapters.first : null,
      to: toLastResolved ? chapters.last : null,
    );
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

  void clearTocSearch() {
    _searchQuery = '';
    _debounce?.cancel();
    _applyFilter();
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
      list = list
          .where(
            (c) => c.title.toLowerCase().contains(_searchQuery.toLowerCase()),
          )
          .toList();
    }
    _displayChapters = _isReversed ? list.reversed.toList() : List.from(list);
    notifyListeners();
  }

  Future<BookDetailOperationResult> changeSource(SearchBook newSource) async {
    if (_isChangingSource) {
      return BookDetailOperationResult.failure('正在換源，請稍候');
    }
    _isChangingSource = true;
    notifyListeners();
    final oldBook = _book.copyWith();
    try {
      final prepared = await _sourceSwitchService.prepareSwitch(
        oldBook,
        newSource,
        targetChapterIndex: oldBook.chapterIndex,
        targetChapterTitle: oldBook.durChapterTitle,
      );
      await _sourceSwitchService.commitSwitch(
        oldBook,
        prepared,
        bookDao: _bookDao,
        chapterDao: _chapterDao,
      );

      _book = prepared.migratedBook;
      _currentSource = prepared.source;
      _allChapters = prepared.chapters;
      _sourceIssueMessage = null;
      try {
        await _refreshCacheStatus(notify: false);
      } catch (e) {
        AppLog.e('換源後更新快取狀態失敗: $e', error: e);
      }
      unawaited(_storeDisplayCover());
      _applyFilter();
      AppEventBus().fire(AppEventBus.upBookshelf);
      return BookDetailOperationResult.success('已切換到 ${_book.originName}');
    } catch (error, stackTrace) {
      if (!isSourceSwitchUnavailable(error)) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      AppLog.e('換源失敗: $error', error: error, stackTrace: stackTrace);
      return BookDetailOperationResult.failure(
        '換源失敗：${userErrorReason(error)}',
      );
    } finally {
      _isChangingSource = false;
      notifyListeners();
    }
  }

  Future<void> toggleInBookshelf() async {
    await setInBookshelf(!isInBookshelf);
  }

  /// 加入或移出書架進行中（加入時可能要先抓目錄、移出時要刪正文與封面）；
  /// 期間不接受反向操作，兩者才不會交錯寫入。
  bool get isUpdatingBookshelf => _isUpdatingBookshelf;
  bool _isUpdatingBookshelf = false;

  Future<BookDetailOperationResult> setInBookshelf(bool value) async {
    if (_isUpdatingBookshelf) {
      return BookDetailOperationResult.failure('正在更新書架，請稍候');
    }
    _isUpdatingBookshelf = true;
    try {
      return await _setInBookshelf(value);
    } finally {
      _isUpdatingBookshelf = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<BookDetailOperationResult> _setInBookshelf(bool value) async {
    if (isInBookshelf == value) {
      return BookDetailOperationResult.success(value ? '已在書架中' : '已移出書架');
    }

    final previous = isInBookshelf;
    _book.isInBookshelf = value;
    notifyListeners();

    if (value) {
      if (_book.syncTime == 0) {
        _book.syncTime = DateTime.now().millisecondsSinceEpoch;
      }
      try {
        if (_allChapters.isEmpty) {
          await _loadChapters();
        }
        _book.fillChapterTitle(_allChapters);
        await _bookDao.upsert(_book);
        await _saveChapterMetadataIfPossible();
      } catch (e) {
        AppLog.e('加入書架失敗: $e', error: e);
        _book.isInBookshelf = previous;
        notifyListeners();
        return BookDetailOperationResult.failure(
          '加入書架失敗：${userErrorReason(e)}',
        );
      }
    } else {
      try {
        await _bookStorageService.discardBook(_book);
      } catch (e) {
        AppLog.e('移出書架失敗: $e', error: e);
        _book.isInBookshelf = previous;
        notifyListeners();
        return BookDetailOperationResult.failure(
          '移出書架失敗：${userErrorReason(e)}',
        );
      }
    }

    AppEventBus().fire(AppEventBus.upBookshelf);
    notifyListeners();
    if (value && supportsBackgroundDownload) {
      // 加入書架的書整本下載（ADR 0008）。
      unawaited(
        _resolvedDownloadService.keepShelfBookDownloaded(_book.bookUrl),
      );
    }
    return BookDetailOperationResult.success(value ? '已加入書架' : '已移出書架');
  }

  Future<BookDetailOperationResult> updateBookInfo(
    String name,
    String author,
    String intro,
    String coverUrl, {
    String? kind,
    String? customTag,
    String? originName,
    String? tocUrl,
  }) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      return BookDetailOperationResult.failure('書名不能為空');
    }

    final next = Book.fromJson(Map<String, dynamic>.from(_book.toJson()));
    next.name = normalizedName;
    next.author = author.trim();
    next.intro = intro.trim();
    next.customIntro = intro.trim();
    next.kind = kind?.trim();
    next.customTag = customTag?.trim();
    if (originName != null && originName.trim().isNotEmpty) {
      next.originName = originName.trim();
    }
    if (tocUrl != null) {
      next.tocUrl = tocUrl.trim();
    }
    // 改過的封面記在 customCoverUrl：顯示時優先、書源更新不會蓋掉。
    final editedCover = coverUrl.trim();
    final currentCover = _book.customCoverUrl ?? _book.coverUrl ?? '';
    if (editedCover != currentCover) {
      next.customCoverUrl = editedCover.isEmpty ? null : editedCover;
      next.customCoverLocalPath = null;
    }

    try {
      await _bookDao.upsert(next);
      _book = next;
      unawaited(_storeDisplayCover());
      notifyListeners();
      return BookDetailOperationResult.success('書籍資訊已儲存');
    } catch (error) {
      AppLog.e('儲存書籍資訊失敗: $error', error: error);
      return BookDetailOperationResult.failure(
        '儲存書籍資訊失敗：${userErrorReason(error)}',
      );
    }
  }

  /// 這本書是否參與下拉與啟動時的書架更新；明確按「檢查更新」時照查。
  Future<BookDetailOperationResult> setCanUpdate(bool value) async {
    try {
      await _bookDao.updateCanUpdate(_book.bookUrl, value);
      _book.canUpdate = value;
      AppEventBus().fire(AppEventBus.upBookshelf);
      notifyListeners();
      return BookDetailOperationResult.success(
        value ? '這本書恢復自動檢查更新' : '這本書不再自動檢查更新',
      );
    } catch (error) {
      AppLog.e('設定自動檢查更新失敗: $error', error: error);
      return BookDetailOperationResult.failure(
        '設定失敗：${userErrorReason(error)}',
      );
    }
  }

  Future<BookDetailOperationResult> updateCover(String url) async {
    final next = Book.fromJson(Map<String, dynamic>.from(_book.toJson()));
    next.customCoverUrl = url.trim();
    next.customCoverLocalPath = null;
    try {
      await _coverStorage.ensureDisplayCoverStored(next);
      await _bookDao.upsert(next);
      _book = next;
      notifyListeners();
      return BookDetailOperationResult.success('封面已更新');
    } catch (error) {
      AppLog.e('更新封面失敗: $error', error: error);
      return BookDetailOperationResult.failure(
        '更新封面失敗：${userErrorReason(error)}',
      );
    }
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
      return BookDetailOperationResult.failure('清除快取失敗：${userErrorReason(e)}');
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
    if (_isCheckingUpdate) {
      return const BookDetailUpdateResult(
        success: false,
        newChapterCount: 0,
        totalChapterCount: 0,
        message: '正在檢查更新',
      );
    }

    _isCheckingUpdate = true;
    notifyListeners();
    try {
      if (_currentSource == null) {
        await _loadSource();
      }
      final source = _currentSource;
      if (source == null || !source.isReadingEnabledByRuntime) {
        throw StateError(_sourceIssueMessage ?? '找不到可閱讀書源');
      }

      // 和書架的檢查共用：書架正在查這本時接上同一次。寫回由共用的檢查
      // 負責，這裡從資料庫重新讀出來顯示。
      final result = await _updates.check(_book.copyWith());
      final saved = await _bookDao.getByUrl(_book.bookUrl);
      if (saved != null) _book = saved;
      if (result.failed) throw result.error!;
      _allChapters = await _chapterDao.getByBook(_book.bookUrl);
      _clearBookInfoDegradation();
      await _refreshCacheStatus(notify: false);
      _applyFilter();
      AppEventBus().fire(AppEventBus.upBookshelf);
      final newCount = result.newChapterCount;
      final total = _allChapters.length;
      return BookDetailUpdateResult(
        success: true,
        newChapterCount: newCount,
        totalChapterCount: total,
        message: newCount > 0 ? '發現 $newCount 個新章節' : '已是最新，總共 $total 章',
      );
    } catch (e) {
      AppLog.e('檢查書籍更新失敗: $e', error: e);
      return BookDetailUpdateResult(
        success: false,
        newChapterCount: 0,
        totalChapterCount: _allChapters.length,
        message: failureMessage('檢查更新', e),
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

  Future<Set<String>> _storedChapterUrls() async {
    final chapterContentDao = _chapterContentDao;
    if (chapterContentDao == null) return <String>{};
    return chapterContentDao.getStoredChapterUrls(
      origin: _book.origin,
      bookUrl: _book.bookUrl,
    );
  }

  Future<void> _clearStoredContent() async {
    // 排版快取由正文算出，正文清掉就一起清。
    await ReaderLayoutCache.deleteBook(_book.bookUrl);
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
      final entries = chapterContentDao == null
          ? const <ReaderChapterContentEntry>[]
          : await chapterContentDao.getEntriesByBookUrls(<String>[
              _book.bookUrl,
            ]);
      // 只算目前目錄裡的章節（依網址）；舊目錄留下的正文不算進進度。
      final readableUrls = {
        for (final chapter in _allChapters)
          if (chapterHasContent(chapter)) chapter.url,
      };
      final storedUrls = <String>{};
      var contentBytes = 0;
      var latestUpdatedAt = 0;
      for (final entry in entries) {
        if (entry.origin != _book.origin ||
            !entry.isReady ||
            !entry.hasDisplayContent) {
          continue;
        }
        if (readableUrls.contains(entry.chapterUrl)) {
          storedUrls.add(entry.chapterUrl);
        }
        final content = entry.content;
        if (content != null && content.isNotEmpty) {
          contentBytes += utf8.encode(content).length;
        }
        latestUpdatedAt = math.max(latestUpdatedAt, entry.updatedAt);
      }

      final coverBytes = await _coverStorage.getBookAssetSize(_book);
      _cacheStatus = BookDetailCacheStatus(
        storedChapterCount: storedUrls.length,
        totalChapterCount: readableUrls.length,
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
    try {
      await _coverStorage.ensureDisplayCoverStored(_book);
      await _bookDao.upsert(_book);
      _announceCover();
      if (hasReadyWorld && !_disposed) notifyListeners();
    } catch (error) {
      AppLog.e('儲存顯示封面失敗: $error', error: error);
    }
  }

  /// 詳情頁常讀到搜尋結果沒有的封面，或已把封面存到手機；告訴搜尋頁，
  /// 回去時同一本書的卡片沿用。
  void _announceCover() {
    final cover = _book.getDisplayCover();
    if (cover == null || cover.isEmpty) return;
    AppEventBus().fire(
      AppEventBus.bookCover,
      data: BookCoverEvent(bookUrl: _book.bookUrl, cover: cover),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _switchSub?.cancel();
    super.dispose();
  }
}
