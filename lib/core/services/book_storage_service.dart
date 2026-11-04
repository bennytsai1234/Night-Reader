import 'dart:io';

import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/download_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/services/book_cover_storage_service.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/download_service.dart';
import 'package:night_reader/core/services/local_book_service.dart';
import 'package:night_reader/core/storage/app_storage_paths.dart';
import 'package:night_reader/core/storage/reader_layout_cache.dart';
import 'package:path/path.dart' as p;

class BookStorageService {
  BookStorageService({
    BookDao? bookDao,
    ChapterDao? chapterDao,
    ReaderChapterContentDao? contentDao,
    DownloadDao? downloadDao,
    DownloadService? downloadService,
    BookCoverStorageService? coverStorage,
  }) : _bookDao = bookDao ?? getIt<BookDao>(),
       _chapterDao = chapterDao ?? getIt<ChapterDao>(),
       _contentDao =
           contentDao ??
           (getIt.isRegistered<ReaderChapterContentDao>()
               ? getIt<ReaderChapterContentDao>()
               : null),
       _downloadDao =
           downloadDao ??
           (getIt.isRegistered<DownloadDao>() ? getIt<DownloadDao>() : null),
       _downloadService =
           downloadService ??
           (getIt.isRegistered<DownloadDao>() ? DownloadService() : null),
       _coverStorage = coverStorage ?? BookCoverStorageService();

  final BookDao _bookDao;
  final ChapterDao _chapterDao;
  final ReaderChapterContentDao? _contentDao;
  final DownloadDao? _downloadDao;
  final DownloadService? _downloadService;
  final BookCoverStorageService _coverStorage;

  Future<void> discardBook(Book book) async {
    if (_downloadService != null) {
      await _downloadService.retireBook(book.bookUrl);
    } else {
      await _downloadDao?.deleteByUrl(book.bookUrl);
    }
    await _contentDao?.deleteByBook(book.origin, book.bookUrl);
    await _chapterDao.deleteByBook(book.bookUrl);
    await _bookDao.deleteByUrl(book.bookUrl);
    await _coverStorage.deleteBookAssets(book);
    await ReaderLayoutCache.deleteBook(book.bookUrl);
    if (book.isLocal) await _deleteLocalOriginal(book);
  }

  /// 本地書移出書架後，App 資料夾裡那份原檔沒有別的書用，跟著刪掉；不在
  /// App 資料夾裡的（很舊的版本直接指著選檔器給的檔）不動。
  static Future<void> _deleteLocalOriginal(Book book) async {
    final path = LocalBookService.filePathOf(book);
    try {
      final dir = await AppStoragePaths.localBooksDir();
      if (!p.isWithin(dir.path, path)) return;
      final file = File(path);
      if (await file.exists()) await file.delete();
    } on FileSystemException catch (error) {
      AppLog.e('刪除本地書原檔失敗', error: error);
    }
  }
}
