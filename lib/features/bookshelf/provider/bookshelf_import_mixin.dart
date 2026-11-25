import 'package:night_reader/core/comic/comic_chapter_files.dart';
import 'package:night_reader/core/diagnostics/app_log_service.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/local_book/local_book_service.dart';
import 'package:night_reader/core/comic/local_comic_service.dart';
import 'package:path/path.dart' as p;

import 'bookshelf_provider_base.dart';

/// BookshelfProvider 的本地書籍匯入邏輯擴展
mixin BookshelfImportMixin on BookshelfProviderBase {
  /// 書架上已經有同一個檔（原檔指紋相同）也算成功，不再加一次。
  Future<bool> importLocalBookPath(String path) async {
    isLoading = true;
    notifyListeners();
    try {
      if (!await _importOne(path)) return false;
      await loadBooks();
      return true;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// 一次加入選好的好幾個檔（書架「加入本地書」的多選）。其中一個失敗不
  /// 影響其他：每一本各自匯入，最後只重讀一次書架。傳回成功的本數與失敗的
  /// 檔名（不含副檔名）。[onProgress] 每做完一本（含失敗的）呼叫一次。
  Future<({int added, List<String> failed})> importLocalBookPaths(
    List<String> paths, {
    void Function(int done, int total)? onProgress,
  }) async {
    isLoading = true;
    notifyListeners();
    var added = 0;
    var done = 0;
    final failed = <String>[];
    onProgress?.call(done, paths.length);
    try {
      for (final path in paths) {
        try {
          if (await _importOne(path)) {
            added += 1;
          } else {
            failed.add(p.basenameWithoutExtension(path));
          }
        } catch (error, stackTrace) {
          AppLog.e('匯入本地書失敗: $error', error: error, stackTrace: stackTrace);
          failed.add(p.basenameWithoutExtension(path));
        } finally {
          done += 1;
          onProgress?.call(done, paths.length);
        }
      }
      await loadBooks();
    } finally {
      isLoading = false;
      notifyListeners();
    }
    return (added: added, failed: failed);
  }

  /// 一個檔加入書架：單一個 CBZ／ZIP 是只有一話的本地漫畫（ADR 0052），
  /// 其他照 TXT／EPUB 匯入。成功（包含書架上已經有同一個檔）回傳 true。
  Future<bool> _importOne(String path) async {
    if (ComicChapterFiles.isArchive(path)) {
      return await importLocalComic(path) != null;
    }
    final book = await LocalBookService().addToShelf(
      path,
      bookDao: bookDao,
      chapterDao: chapterDao,
    );
    return book != null;
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
