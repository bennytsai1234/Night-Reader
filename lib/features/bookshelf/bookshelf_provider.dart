import 'dart:async';

import 'package:night_reader/core/engine/app_event_bus.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/book_storage_service.dart';

import 'provider/bookshelf_provider_base.dart';
import 'provider/bookshelf_logic_mixin.dart';
import 'provider/bookshelf_update_mixin.dart';
import 'provider/bookshelf_import_mixin.dart';

export 'provider/bookshelf_provider_base.dart'
    show BookshelfSortMode, BookshelfSortModeLabel;

export 'package:night_reader/core/services/book_update_service.dart'
    show BookUpdateCheckResult;

class BookshelfProvider extends BookshelfProviderBase
    with BookshelfLogicMixin, BookshelfUpdateMixin, BookshelfImportMixin {
  BookshelfProvider({
    BookStorageService? bookStorageService,
    super.keepBookDownloaded,
    super.startTimer,
  }) : _bookStorageService = bookStorageService ?? BookStorageService() {
    loadUiPreferences();
    loadBooks();
    _bookshelfSub = AppEventBus().onName(AppEventBus.upBookshelf).listen((_) {
      if (_covered) {
        _reloadWhenUncovered = true;
        return;
      }
      unawaited(loadBooks());
    });
  }

  final BookStorageService _bookStorageService;
  StreamSubscription<AppEvent>? _bookshelfSub;

  /// 書架被別的頁面蓋著（[setCovered]）：背景下載完成要重讀時先記著，露出
  /// 來才讀。蓋著的書架仍在元件樹裡，重讀會整頁重建、書卡移位，正好疊在
  /// 上面那頁的換頁動畫上。
  bool _covered = false;
  bool _reloadWhenUncovered = false;

  void setCovered(bool covered) {
    _covered = covered;
    if (covered || !_reloadWhenUncovered) return;
    _reloadWhenUncovered = false;
    unawaited(loadBooks());
  }

  @override
  Future<void> loadBooks() async {
    // 書架上已經有書時，載入中不換回骨架，開始時通知只會讓整頁白白重建
    // 一次（書架檢查、下載完成都會重讀）；空書架或上次失敗時才要畫骨架。
    final showsLoading = books.isEmpty || loadErrorMessage != null;
    isLoading = true;
    loadErrorMessage = null;
    if (showsLoading) notifyListeners();
    try {
      books = await bookDao.getInBookshelf();
      _sortBooks();
      rememberShelf(books);
    } catch (error, stackTrace) {
      AppLog.e('載入書架失敗: $error', error: error, stackTrace: stackTrace);
      loadErrorMessage = '書架載入失敗，請重試';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void _sortBooks() {
    switch (sortMode) {
      case BookshelfSortMode.custom:
        books.sort((a, b) => a.order.compareTo(b.order));
        break;
      case BookshelfSortMode.recentRead:
        books.sort((a, b) => b.durChapterTime.compareTo(a.durChapterTime));
        break;
      case BookshelfSortMode.addedTime:
        books.sort((a, b) => _addedTimeOf(b).compareTo(_addedTimeOf(a)));
        break;
      case BookshelfSortMode.updateTime:
        books.sort((a, b) => _updateTimeOf(b).compareTo(_updateTimeOf(a)));
        break;
      case BookshelfSortMode.bookName:
        books.sort((a, b) => a.name.compareTo(b.name));
        break;
      case BookshelfSortMode.author:
        books.sort((a, b) {
          final author = a.author.compareTo(b.author);
          return author != 0 ? author : a.name.compareTo(b.name);
        });
        break;
    }
  }

  int _addedTimeOf(Book book) {
    if (book.syncTime > 0) return book.syncTime;
    if (book.durChapterTime > 0) return book.durChapterTime;
    return book.latestChapterTime;
  }

  int _updateTimeOf(Book book) {
    if (book.latestChapterTime > 0) return book.latestChapterTime;
    return book.lastCheckTime;
  }

  Future<void> deleteBook(String url) => deleteBooks({url});

  /// 刪除多本書（正文、目錄、封面、下載任務一起清掉），最後只重新載入一次
  /// 書架；中途失敗時已刪掉的照樣反映在書架上，再把錯誤往外丟。
  Future<void> deleteBooks(Set<String> urls) async {
    try {
      for (final url in urls) {
        final book = await bookDao.getByUrl(url);
        if (book == null) continue;
        await _bookStorageService.discardBook(book);
      }
    } finally {
      await loadBooks();
    }
  }

  @override
  void dispose() {
    _bookshelfSub?.cancel();
    super.dispose();
  }
}
