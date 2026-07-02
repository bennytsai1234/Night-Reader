import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/engine/app_event_bus.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';

class ReaderV2SessionFacade {
  const ReaderV2SessionFacade();

  Future<void> addCurrentBookToBookshelf({
    required Book book,
    required List<BookChapter> chapters,
    required ReaderV2Location location,
    required String chapterTitle,
    required BookDao bookDao,
    required ChapterDao chapterDao,
    void Function()? onCompleted,
  }) async {
    book.chapterIndex = location.chapterIndex;
    book.charOffset = location.charOffset;
    book.visualOffsetPx = location.visualOffsetPx;
    book.durChapterTitle = chapterTitle;
    book.readerAnchorJson = null;
    book.durChapterTime = DateTime.now().millisecondsSinceEpoch;
    if (book.syncTime == 0) {
      book.syncTime = DateTime.now().millisecondsSinceEpoch;
    }
    if (chapters.isNotEmpty) {
      book.totalChapterNum = chapters.length;
    }
    book.isInBookshelf = true;
    await bookDao.upsert(book);
    if (chapters.isNotEmpty) {
      await chapterDao.insertChapters(chapters);
    }
    AppEventBus().fire(AppEventBus.upBookshelf, data: book.bookUrl);
    onCompleted?.call();
  }
}
