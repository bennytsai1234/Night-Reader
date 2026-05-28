import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/bookshelf_exchange_service.dart';
import 'package:night_reader/core/services/download_service.dart';
import 'package:night_reader/core/services/event_bus.dart';
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
  Future<void> refreshBookshelf() async {
    final onlineBooks = books.where((b) => !b.isLocal).toList();
    if (onlineBooks.isEmpty) return;

    AppEventBus().fire(AppEvent('bookshelfRefreshStart'));
    var completed = 0;
    final updateTasks = <Future<void>>[];

    for (var book in onlineBooks) {
      updateTasks.add(
        Future(() async {
          try {
            await checkBookUpdate(book);
          } catch (_) {}
          completed++;
          updatingCount = onlineBooks.length - completed;
          notifyListeners();
        }),
      );
    }

    await Future.wait(updateTasks);
    updatingCount = 0;
    loadBooks();
    AppEventBus().fire(AppEvent('bookshelfRefreshEnd'));
  }

  Future<BookUpdateCheckResult> checkBookUpdate(Book book) async {
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

      final oldTotal =
          book.totalChapterNum > 0 ? book.totalChapterNum : chapters.length;
      final newCount =
          chapters.length > oldTotal ? chapters.length - oldTotal : 0;
      info.isInBookshelf = true;
      info.group = book.group;
      info.order = book.order;
      info.syncTime = book.syncTime;
      info.chapterIndex = book.chapterIndex;
      info.charOffset = book.charOffset;
      info.visualOffsetPx = book.visualOffsetPx;
      info.durChapterTitle = book.durChapterTitle;
      info.durChapterTime = book.durChapterTime;
      info.readerAnchorJson = book.readerAnchorJson;
      info.canUpdate = book.canUpdate;
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
      return BookUpdateCheckResult(
        bookUrl: book.bookUrl,
        newChapterCount: newCount,
      );
    } catch (e) {
      AppLog.w('檢查書籍更新失敗 ${book.name}: $e');
      book.lastCheckTime = checkedAt;
      await bookDao.upsert(book);
      return BookUpdateCheckResult(
        bookUrl: book.bookUrl,
        newChapterCount: 0,
        error: e,
      );
    }
  }

  Future<List<BookUpdateCheckResult>> batchCheckUpdate(Set<String> urls) async {
    final selected = await _booksForUrls(urls);
    final results = <BookUpdateCheckResult>[];
    updatingCount = selected.where((book) => !book.isLocal).length;
    notifyListeners();
    try {
      for (final book in selected) {
        results.add(await checkBookUpdate(book));
        updatingCount = (updatingCount - 1).clamp(0, selected.length).toInt();
        notifyListeners();
      }
      await loadBooks();
      return results;
    } finally {
      updatingCount = 0;
      notifyListeners();
    }
  }

  Future<BookshelfBatchDownloadResult> batchDownload(Set<String> urls) async {
    final selected = await _booksForUrls(urls);
    final contentDao =
        getIt.isRegistered<ReaderChapterContentDao>()
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
        chapters = await service.getChapterList(source, book);
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

      var toDownload = chapters;
      if (contentDao != null) {
        final stored = await ReaderChapterContentStore(
          chapterDao: chapterDao,
          contentDao: contentDao,
        ).storedChapterIndices(book: book);
        toDownload =
            chapters
                .where((chapter) => !stored.contains(chapter.index))
                .toList();
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
