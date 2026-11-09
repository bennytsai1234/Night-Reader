import 'package:night_reader/core/comic/comic_chapter_files.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/services/local_book_service.dart';
import 'package:night_reader/core/services/local_comic_service.dart';

import 'bookshelf_provider_base.dart';

/// BookshelfProvider 的本地書籍匯入邏輯擴展
mixin BookshelfImportMixin on BookshelfProviderBase {
  /// 書架上已經有同一個檔（原檔指紋相同）也算成功，不再加一次。
  Future<bool> importLocalBookPath(String path) async {
    // 單一個 CBZ／ZIP 是只有一話的本地漫畫（ADR 0052）。
    if (ComicChapterFiles.isArchive(path)) {
      return await importLocalComic(path) != null;
    }
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

  /// 匯入本地漫畫（作品資料夾或單一個 CBZ／ZIP），傳回書架上的那本；裡面
  /// 沒有漫畫時傳回 null。[onProgress] 每整理好一話呼叫一次。
  Future<Book?> importLocalComic(
    String path, {
    void Function(int done, int total)? onProgress,
  }) async {
    final book = await LocalComicService(
      bookDao: bookDao,
      chapterDao: chapterDao,
    ).importPath(path, onProgress: onProgress);
    if (book != null) await loadBooks();
    return book;
  }
}
