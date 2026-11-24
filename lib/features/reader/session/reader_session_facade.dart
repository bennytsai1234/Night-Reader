import 'dart:convert';

import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/engine/app_event_bus.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/features/reader/session/reader_location.dart';
import 'package:night_reader/features/reader/session/reader_open_target.dart';

class ReaderSessionFacade {
  const ReaderSessionFacade();

  Future<void> addCurrentBookToBookshelf({
    required Book book,
    required List<BookChapter> chapters,
    required ReaderLocation location,
    required String chapterTitle,
    required BookDao bookDao,
    required ChapterDao chapterDao,
    void Function()? onCompleted,
  }) async {
    book.chapterIndex = location.chapterIndex;
    book.charOffset = location.charOffset;
    book.visualOffsetPx = location.visualOffsetPx;
    book.durChapterTitle = chapterTitle;
    // 重開時照前後文字找回同一句（ADR 0042）：[location] 自己帶著就用它的，
    // 沒帶時留下退出前剛存、指著同一個位置的那份；都沒有才只存章節與字數。
    final anchor = location.hasContentIdentity
        ? location
        : ReaderOpenTarget.resume(book).location;
    book.readerAnchorJson = anchor.hasContentIdentity
        ? jsonEncode(
            anchor.copyWith(visualOffsetPx: location.visualOffsetPx).toJson(),
          )
        : null;
    book.durChapterTime = DateTime.now().millisecondsSinceEpoch;
    book.progressTime = book.durChapterTime;
    if (book.syncTime == 0) {
      book.syncTime = DateTime.now().millisecondsSinceEpoch;
    }
    if (chapters.isNotEmpty) {
      book.totalChapterNum = chapters.length;
    }
    book.isInBookshelf = true;
    // 只寫閱讀器管的這幾欄：閱讀中在書籍詳情改的書名、封面不被手上這份蓋回去。
    await bookDao.saveShelfEntry(book, withChapterCount: chapters.isNotEmpty);
    if (chapters.isNotEmpty) {
      await chapterDao.insertChapters(chapters);
    }
    AppEventBus().fire(AppEventBus.upBookshelf, data: book.bookUrl);
    onCompleted?.call();
  }
}
