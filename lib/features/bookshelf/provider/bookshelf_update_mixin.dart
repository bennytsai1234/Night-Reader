import 'dart:async';

import 'package:pool/pool.dart';
import 'package:night_reader/core/config/app_config.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/bookshelf_exchange_service.dart';
import 'package:night_reader/core/services/download_service.dart';
import 'package:night_reader/core/services/reader_chapter_content_store.dart';

import 'bookshelf_provider_base.dart';

class BookshelfBatchDownloadResult {
  const BookshelfBatchDownloadResult({
    required this.queuedBooks,
    required this.queuedChapters,
    required this.skippedBooks,
  });

  final int queuedBooks;
  final int queuedChapters;
  final int skippedBooks;
}

class BookUpdateCheckResult {
  const BookUpdateCheckResult({
    required this.bookUrl,
    required this.newChapterCount,
    this.error,
  });

  final String bookUrl;
  final int newChapterCount;
  final Object? error;

  bool get hasUpdate => newChapterCount > 0;
  bool get failed => error != null;
}

/// BookshelfProvider 的更新與網絡同步邏輯擴展
mixin BookshelfUpdateMixin on BookshelfProviderBase {
  /// 書架更新同時檢查的書數，與目錄多頁抓取的並行數（4）相同：書架上
  /// 幾十本書不會一起發請求、一起在 UI isolate 上解析目錄。
  static const int _refreshConcurrency = 4;

  Future<void>? _refreshing;

  /// 這次檢查有沒有使用者手動下拉（包括下拉時接上已在跑的那次）；只有手動
  /// 時才標出檢查失敗的書。
  bool _userRefreshed = false;

  /// 書架檢查後角標掛多久（DESIGN.md「書籍卡片與清單」）。
  static const Duration updateBadgeDuration = Duration(seconds: 5);

  /// 上一次書架檢查的結果，只留有新章節或檢查失敗的書；不存檔，
  /// [updateBadgeDuration] 後一起清掉。
  Map<String, BookUpdateCheckResult> _updateBadges = const {};
  Timer? _updateBadgeTimer;

  /// 書卡角標：有新章節（+N）或檢查失敗（!）；沒有就是 null。
  BookUpdateCheckResult? updateBadgeOf(String bookUrl) =>
      _updateBadges[bookUrl];

  /// 開 App 後在背景做的事：先把書架上還沒下載完整的書排進下載（ADR
  /// 0007），再檢查更新（「啟動時檢查書架更新」關掉時不檢查）。
  Future<void> onAppLaunch() async {
    await keepShelfDownloaded();
    if (!AppConfig.autoRefresh) return;
    await refreshBookshelf();
  }

  /// 書架上每本網路書都排一次自動下載；不看 [Book.canUpdate]，那只管要不要
  /// 檢查新章節，目錄裡已有的章節照樣下載。
  Future<void> keepShelfDownloaded() async {
    final List<Book> shelf;
    try {
      shelf = await bookDao.getInBookshelf();
    } catch (error) {
      AppLog.w('書架自動下載讀取書架失敗: $error');
      return;
    }
    for (final book in shelf) {
      if (book.isLocal) continue;
      await _keepDownloaded(book.bookUrl);
    }
  }

  Future<void> _keepDownloaded(
    String bookUrl, {
    bool hasNewChapters = false,
  }) async {
    try {
      await keepBookDownloaded(bookUrl, hasNewChapters: hasNewChapters);
    } catch (error) {
      AppLog.w('書架自動下載排程失敗 $bookUrl: $error');
    }
  }

  /// 下拉與啟動時的書架更新：在背景檢查，不轉圈，不改 [updatingCount]（那是
  /// 多選檢查的進度）；檢查完在書卡上掛 [updateBadgeDuration] 的角標，有新
  /// 章節一律標，檢查失敗只在 [userInitiated]（手動下拉）時標。略過本地書與
  /// 使用者關掉「自動檢查更新」的書；已在檢查時沿用同一次，不重複發請求。
  Future<void> refreshBookshelf({bool userInitiated = false}) {
    if (userInitiated) _userRefreshed = true;
    final running = _refreshing;
    if (running != null) return running;
    final refresh = _refreshAll().whenComplete(() {
      _refreshing = null;
      _userRefreshed = false;
      notifyListeners();
    });
    _refreshing = refresh;
    notifyListeners();
    return refresh;
  }

  /// 下拉或開 App 的書架檢查正在進行；書架頁首的「書架」字樣這時掃過淡墨
  /// 流光。多選的「檢查更新」看 [updatingCount]，不算在這裡。
  bool get isCheckingShelf => _refreshing != null;

  Future<void> _refreshAll() async {
    // 從資料庫讀：啟動時書架可能還沒載入完，記憶體裡的清單也可能是舊的。
    final targets = (await bookDao.getInBookshelf())
        .where((book) => !book.isLocal && book.canUpdate)
        .toList();
    if (targets.isEmpty) return;

    final pool = Pool(_refreshConcurrency);
    final List<BookUpdateCheckResult?> results;
    try {
      results = await Future.wait([
        for (final book in targets)
          pool.withResource(() async {
            try {
              return await checkBookUpdate(book);
            } catch (_) {
              return null;
            }
          }),
      ]);
    } finally {
      await pool.close();
    }
    _updateBadgeTimer?.cancel();
    _updateBadges = {
      for (final result in results.nonNulls)
        if (result.hasUpdate || (result.failed && _userRefreshed))
          result.bookUrl: result,
    };
    await loadBooks();
    if (_updateBadges.isEmpty) return;
    _updateBadgeTimer = startTimer(updateBadgeDuration, () {
      _updateBadgeTimer = null;
      _updateBadges = const {};
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _updateBadgeTimer?.cancel();
    super.dispose();
  }

  /// 正在檢查的書。下拉、開 App 的檢查和明確按「檢查更新」可能同時查到
  /// 同一本：後到的接上同一次，不重發請求，也不會因為先到的那次已寫入新
  /// 目錄，就把新章節數算成 0。
  final Map<String, Future<BookUpdateCheckResult>> _checking = {};

  /// 抓書源上的詳情與目錄寫回這本書。網路請求期間使用者可能在讀這本書、
  /// 改了設定或把它移出書架，所以寫回時以資料庫裡最新的一筆為準，只換掉
  /// 書源給的欄位。
  Future<BookUpdateCheckResult> checkBookUpdate(Book book) {
    // 不能寫成 `=> _checking.remove(...)`：remove 回傳的就是這個 Future，
    // whenComplete 會等它，變成自己等自己。
    return _checking[book.bookUrl] ??= _checkBookUpdate(book).whenComplete(() {
      _checking.remove(book.bookUrl);
    });
  }

  Future<BookUpdateCheckResult> _checkBookUpdate(Book book) async {
    if (book.isLocal) {
      return BookUpdateCheckResult(bookUrl: book.bookUrl, newChapterCount: 0);
    }

    final checkedAt = DateTime.now().millisecondsSinceEpoch;
    try {
      final source = await sourceDao.getByUrl(book.origin);
      if (source == null || !source.isReadingEnabledByRuntime) {
        throw StateError('找不到可閱讀書源');
      }
      final info = await service.getBookInfo(source, book);
      final chapters = await service.getChapterList(source, info);
      info.bookUrl = book.bookUrl;
      info.origin = book.origin;
      info.originName = book.originName;
      if (info.tocUrl.isEmpty) {
        info.tocUrl = book.tocUrl;
      }
      for (var i = 0; i < chapters.length; i++) {
        chapters[i].index = i;
        chapters[i].bookUrl = book.bookUrl;
      }

      final newCount = await bookDao.transaction<int?>(() async {
        final current = await bookDao.getByUrl(book.bookUrl);
        // 檢查期間移出書架或換了書源：不寫回，免得書又回到書架上。
        if (current == null ||
            !current.isInBookshelf ||
            current.origin != book.origin) {
          return null;
        }
        final oldTotal = current.totalChapterNum > 0
            ? current.totalChapterNum
            : chapters.length;
        final newCount = chapters.length > oldTotal
            ? chapters.length - oldTotal
            : 0;
        info.isInBookshelf = true;
        info.group = current.group;
        info.order = current.order;
        info.syncTime = current.syncTime;
        info.chapterIndex = current.chapterIndex;
        info.charOffset = current.charOffset;
        info.visualOffsetPx = current.visualOffsetPx;
        info.durChapterTitle = current.durChapterTitle;
        info.durChapterTime = current.durChapterTime;
        info.readerAnchorJson = current.readerAnchorJson;
        info.canUpdate = current.canUpdate;
        info.customCoverUrl = current.customCoverUrl;
        info.customCoverLocalPath = current.customCoverLocalPath;
        info.customIntro = current.customIntro;
        info.customTag = current.customTag;
        info.readConfig = current.readConfig;
        info.lastCheckTime = checkedAt;
        info.lastCheckCount = newCount;
        info.totalChapterNum = chapters.length;
        if (chapters.isNotEmpty) {
          info.latestChapterTitle = chapters.last.title;
          if (newCount > 0) {
            info.latestChapterTime = checkedAt;
          }
        }
        await bookDao.upsert(info);
        if (chapters.isNotEmpty) {
          await chapterDao.insertChapters(chapters);
        }
        return newCount;
      });
      if (newCount == null) {
        return BookUpdateCheckResult(bookUrl: book.bookUrl, newChapterCount: 0);
      }
      // 目錄寫好了：新章節（或之前沒排到的章節）接著下載。
      await _keepDownloaded(book.bookUrl, hasNewChapters: newCount > 0);
      return BookUpdateCheckResult(
        bookUrl: book.bookUrl,
        newChapterCount: newCount,
      );
    } catch (e) {
      AppLog.w('檢查書籍更新失敗 ${book.name}: $e');
      await bookDao.updateLastCheckTime(book.bookUrl, checkedAt);
      return BookUpdateCheckResult(
        bookUrl: book.bookUrl,
        newChapterCount: 0,
        error: e,
      );
    }
  }

  /// 這本書是否參與下拉與啟動時的書架更新；明確對它按「檢查更新」時照查。
  Future<void> setBookCanUpdate(Book book, bool value) async {
    await bookDao.updateCanUpdate(book.bookUrl, value);
    book.canUpdate = value;
    notifyListeners();
  }

  /// 明確選了這些書才檢查，所以不看 [Book.canUpdate]。
  Future<List<BookUpdateCheckResult>> batchCheckUpdate(Set<String> urls) async {
    final selected = await _booksForUrls(urls);
    final results = <BookUpdateCheckResult>[];
    // 以增減計數：單本與批次的檢查可能同時進行，先結束的那次只扣掉自己的
    // 剩餘數，不會把另一次的進度歸零。
    var remaining = selected.where((book) => !book.isLocal).length;
    updatingCount += remaining;
    notifyListeners();
    try {
      for (final book in selected) {
        results.add(await checkBookUpdate(book));
        if (!book.isLocal && remaining > 0) {
          remaining--;
          updatingCount--;
          notifyListeners();
        }
      }
      await loadBooks();
      return results;
    } finally {
      updatingCount -= remaining;
      notifyListeners();
    }
  }

  Future<BookshelfBatchDownloadResult> batchDownload(Set<String> urls) async {
    final selected = await _booksForUrls(urls);
    final contentDao = getIt.isRegistered<ReaderChapterContentDao>()
        ? getIt<ReaderChapterContentDao>()
        : null;
    final downloadService = DownloadService();
    var queuedBooks = 0;
    var queuedChapters = 0;
    var skippedBooks = 0;

    for (final book in selected) {
      if (book.isLocal) {
        skippedBooks++;
        continue;
      }
      final source = await sourceDao.getByUrl(book.origin);
      if (source == null || !source.isReadingEnabledByRuntime) {
        skippedBooks++;
        continue;
      }

      var chapters = await chapterDao.getByBook(book.bookUrl);
      if (chapters.isEmpty) {
        // 一本書抓不到目錄只略過這本，不中斷整批（前面的書已經加入佇列）。
        try {
          chapters = await service.getChapterList(source, book);
        } catch (error, stackTrace) {
          AppLog.e(
            '批次下載取得目錄失敗: ${book.name}',
            error: error,
            stackTrace: stackTrace,
          );
          skippedBooks++;
          continue;
        }
        for (var i = 0; i < chapters.length; i++) {
          chapters[i].index = i;
          chapters[i].bookUrl = book.bookUrl;
        }
        await chapterDao.insertChapters(chapters);
      }
      if (chapters.isEmpty) {
        skippedBooks++;
        continue;
      }

      var toDownload = chapters.where(chapterHasContent).toList();
      if (contentDao != null) {
        toDownload = await ReaderChapterContentStore(
          chapterDao: chapterDao,
          contentDao: contentDao,
        ).missingChapters(book: book, chapters: chapters);
      }
      if (toDownload.isEmpty) {
        skippedBooks++;
        continue;
      }
      await downloadService.addDownloadTask(book, toDownload);
      queuedBooks++;
      queuedChapters += toDownload.length;
    }

    return BookshelfBatchDownloadResult(
      queuedBooks: queuedBooks,
      queuedChapters: queuedChapters,
      skippedBooks: skippedBooks,
    );
  }

  Future<BookshelfBatchDownloadResult> batchEnsureComplete(
    Set<String> urls,
  ) async {
    final selected = await _booksForUrls(urls);
    final contentDao = getIt.isRegistered<ReaderChapterContentDao>()
        ? getIt<ReaderChapterContentDao>()
        : null;
    final downloadService = DownloadService();
    var queuedBooks = 0;
    var queuedChapters = 0;
    var skippedBooks = 0;

    for (final book in selected) {
      if (book.isLocal) {
        skippedBooks++;
        continue;
      }
      final source = await sourceDao.getByUrl(book.origin);
      if (source == null || !source.isReadingEnabledByRuntime) {
        skippedBooks++;
        continue;
      }

      // 永遠重抓最新章節目錄；失敗時 fallback 到本地快取
      List<BookChapter> chapters;
      try {
        final fetched = await service.getChapterList(source, book);
        for (var i = 0; i < fetched.length; i++) {
          fetched[i].index = i;
          fetched[i].bookUrl = book.bookUrl;
        }
        if (fetched.isNotEmpty) {
          await chapterDao.insertChapters(fetched);
        }
        chapters = fetched;
      } catch (e) {
        AppLog.w('整本書補下載：取得章節目錄失敗 ${book.name}: $e');
        chapters = await chapterDao.getByBook(book.bookUrl);
      }

      if (chapters.isEmpty) {
        skippedBooks++;
        continue;
      }

      var toDownload = chapters.where(chapterHasContent).toList();
      if (contentDao != null) {
        toDownload = await ReaderChapterContentStore(
          chapterDao: chapterDao,
          contentDao: contentDao,
        ).missingChapters(book: book, chapters: chapters);
      }
      if (toDownload.isEmpty) {
        skippedBooks++;
        continue;
      }

      await downloadService.addDownloadTask(book, toDownload);
      queuedBooks++;
      queuedChapters += toDownload.length;
    }

    return BookshelfBatchDownloadResult(
      queuedBooks: queuedBooks,
      queuedChapters: queuedChapters,
      skippedBooks: skippedBooks,
    );
  }

  Future<List<Book>> _booksForUrls(Set<String> urls) async {
    final selected = <Book>[];
    for (final url in urls) {
      final book = await bookDao.getByUrl(url);
      if (book != null) selected.add(book);
    }
    return selected;
  }

  Future<void> importBookshelfFromUrl(String url) async {
    isLoading = true;
    notifyListeners();
    try {
      await BookshelfExchangeService().importFromUrl(url);
      await loadBooks();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}
