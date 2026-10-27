import 'dart:io';

import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/book_cover_storage_service.dart';
import 'package:night_reader/core/services/local_book_service.dart';

import 'bookshelf_provider_base.dart';

/// BookshelfProvider 的本地書籍匯入邏輯擴展
mixin BookshelfImportMixin on BookshelfProviderBase {
  Future<bool> importLocalBookPath(String path) async {
    final storedPath = await LocalBookService().storeInLibrary(path);
    final bookUrl = 'local://$storedPath';
    final existingBook = await bookDao.getByUrl(bookUrl);
    if (existingBook != null && existingBook.isInBookshelf) return true;

    isLoading = true;
    notifyListeners();

    try {
      final result = await LocalBookService().importBook(storedPath);
      if (result != null) {
        result.book.syncTime = result.book.syncTime == 0
            ? DateTime.now().millisecondsSinceEpoch
            : result.book.syncTime;
        result.book.fillChapterTitle(result.chapters);
        final cover = result.cover;
        if (cover != null) {
          await BookCoverStorageService().storeEmbeddedCover(
            result.book,
            cover,
            extension: result.coverExtension ?? '',
          );
        }
        // 書與章節一起寫：章節寫不進去時書也不留，下面才能放心刪掉複本。
        await bookDao.transaction(() async {
          await bookDao.upsert(result.book);
          await chapterDao.insertChapters(result.chapters);
        });
        await loadBooks();
        return true;
      }
      await _discardUnusedCopy(storedPath, existingBook == null);
      return false;
    } catch (e) {
      AppLog.e('匯入本地書籍失敗: $e', error: e);
      await _discardUnusedCopy(storedPath, existingBook == null);
      rethrow;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// 匯入失敗時，沒有任何書指著的那份複本刪掉，不留在本地書資料夾。
  Future<void> _discardUnusedCopy(String path, bool unused) async {
    if (!unused) return;
    try {
      await File(path).delete();
    } on FileSystemException catch (e) {
      AppLog.e('刪除匯入失敗的本地書複本失敗: $e', error: e);
    }
  }
}
