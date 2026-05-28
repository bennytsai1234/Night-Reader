import 'package:reader/core/services/app_log_service.dart';
import 'package:reader/core/services/book_cover_storage_service.dart';
import 'package:reader/core/services/local_book_service.dart';
import 'bookshelf_provider_base.dart';

/// BookshelfProvider 的本地書籍匯入邏輯擴展
mixin BookshelfImportMixin on BookshelfProviderBase {
  Future<bool> importLocalBookPath(String path) async {
    final bookUrl = 'local://$path';
    final existingBook = await bookDao.getByUrl(bookUrl);
    if (existingBook != null && existingBook.isInBookshelf) return true;

    isLoading = true;
    notifyListeners();

    try {
      final result = await LocalBookService().importBook(path);
      if (result != null) {
        result.book.syncTime =
            result.book.syncTime == 0
                ? DateTime.now().millisecondsSinceEpoch
                : result.book.syncTime;
        await BookCoverStorageService().ensureBookCoverStored(result.book);
        await bookDao.upsert(result.book);
        await chapterDao.insertChapters(result.chapters);
        await loadBooks();
        return true;
      }
      return false;
    } catch (e) {
      AppLog.e('匯入本地書籍失敗: $e', error: e);
      rethrow;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}
