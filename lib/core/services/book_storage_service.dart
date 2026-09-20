import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/bookmark_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/download_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/services/book_cover_storage_service.dart';
import 'package:night_reader/core/services/download_service.dart';

class BookStorageService {
  BookStorageService({
    BookDao? bookDao,
    ChapterDao? chapterDao,
    ReaderChapterContentDao? contentDao,
    BookmarkDao? bookmarkDao,
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
       _bookmarkDao =
           bookmarkDao ??
           (getIt.isRegistered<BookmarkDao>() ? getIt<BookmarkDao>() : null),
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
  final BookmarkDao? _bookmarkDao;
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
    await _bookmarkDao?.deleteByBook(book.bookUrl);
    await _chapterDao.deleteByBook(book.bookUrl);
    await _bookDao.deleteByUrl(book.bookUrl);
    await _coverStorage.deleteBookAssets(book);
  }
}
