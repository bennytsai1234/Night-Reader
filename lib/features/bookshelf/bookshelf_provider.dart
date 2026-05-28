import 'dart:async';

import 'package:night_reader/core/engine/app_event_bus.dart';
import 'package:night_reader/core/models/book.dart';

import 'provider/bookshelf_provider_base.dart';
import 'provider/bookshelf_logic_mixin.dart';
import 'provider/bookshelf_update_mixin.dart';
import 'provider/bookshelf_import_mixin.dart';

export 'provider/bookshelf_provider_base.dart'
    show BookshelfSortMode, BookshelfSortModeLabel;
export 'provider/bookshelf_update_mixin.dart'
    show BookshelfBatchDownloadResult, BookUpdateCheckResult;

class BookshelfProvider extends BookshelfProviderBase
    with BookshelfLogicMixin, BookshelfUpdateMixin, BookshelfImportMixin {
  StreamSubscription<AppEvent>? _bookshelfSub;

  BookshelfProvider() {
    loadUiPreferences();
    loadBooks();
    _bookshelfSub = AppEventBus()
        .onName(AppEventBus.upBookshelf)
        .listen((_) => unawaited(loadBooks()));
  }

  @override
  Future<void> loadBooks() async {
    isLoading = true;
    notifyListeners();
    try {
      books = await bookDao.getInBookshelf();
      _sortBooks();
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

  Future<void> removeFromBookshelf(String url) async {
    await bookDao.deleteByUrl(url);
    await loadBooks();
  }

  @override
  void dispose() {
    _bookshelfSub?.cancel();
    super.dispose();
  }
}
