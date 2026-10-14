import 'dart:async';

import 'package:pool/pool.dart';
import 'package:night_reader/core/config/app_config.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/book_toc_replacer.dart';
import 'package:night_reader/core/services/book_update_service.dart';
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

  /// 抓書源上的詳情與目錄寫回這本書；同一本書已在檢查（包括書籍詳情發起
  /// 的）時接上同一次。
  Future<BookUpdateCheckResult> checkBookUpdate(Book book) =>
      updates.check(book);

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

      var toDownload = chapters.where(chapterIsDownloadable).toList();
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

      // 永遠重抓最新章節目錄；失敗時 fallback 到本地快取。抓到的目錄會換掉
      // 舊的，所以目錄分頁要全部抓到。
      List<BookChapter> chapters;
      try {
        final fetched = await service.getChapterList(
          source,
          book,
          requireComplete: true,
        );
        chapters = await _replaceToc(book, fetched, contentDao);
      } catch (e) {
        AppLog.w('整本書補下載：取得章節目錄失敗 ${book.name}: $e');
        chapters = await chapterDao.getByBook(book.bookUrl);
      }

      if (chapters.isEmpty) {
        skippedBooks++;
        continue;
      }

      var toDownload = chapters.where(chapterIsDownloadable).toList();
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

  /// 換上新目錄並回傳寫入的目錄。閱讀進度以資料庫裡最新的一筆為準，抓目錄
  /// 期間閱讀器可能寫了新進度。
  Future<List<BookChapter>> _replaceToc(
    Book book,
    List<BookChapter> fetched,
    ReaderChapterContentDao? contentDao,
  ) {
    return bookDao.transaction(() async {
      final stored = await bookDao.getByUrl(book.bookUrl);
      if (stored == null || stored.origin != book.origin) {
        throw StateError('抓目錄期間這本書已換源或移除');
      }
      final result = await BookTocReplacer(
        chapterDao: chapterDao,
        contentDao: contentDao,
      ).replace(stored, fetched);
      if (result.progressMoved) await bookDao.upsert(stored);
      return result.chapters;
    });
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
