import 'package:night_reader/core/services/local_book_service.dart';

import 'bookshelf_provider_base.dart';

/// BookshelfProvider 的本地書籍匯入邏輯擴展
mixin BookshelfImportMixin on BookshelfProviderBase {
  /// 書架上已經有同一個檔（原檔指紋相同）也算成功，不再加一次。
  Future<bool> importLocalBookPath(String path) async {
    isLoading = true;
    notifyListeners();
    try {
      final book = await LocalBookService().addToShelf(
        path,
        bookDao: bookDao,
        chapterDao: chapterDao,
      );
      if (book == null) return false;
      await loadBooks();
      return true;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}
