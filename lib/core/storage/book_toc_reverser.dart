import 'package:drift/drift.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/bookmark_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/highlight_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';

/// 「反轉目錄」（同 Legado `TocViewModel.reverseToc`）：有些書源給的目錄
/// 是新到舊，讀者替這本書打開後，存著的目錄整個翻過來、之後抓的也照翻
/// （抓目錄時照書的 `reverseToc`，`WebBookService.getChapterList`）。
///
/// 存著的目錄的順序永遠等於「書源給的順序，`reverseToc` 開著時再翻過來」；
/// 這個開關只從這裡改，存著的目錄跟著一起翻。閱讀進度照章節網址對回
/// 同一章（[BookLogic.realignProgress]），書籤與標註的序號跟著換；下載的
/// 正文照章節網址存，不用動。
class BookTocReverser {
  BookTocReverser({
    BookDao? bookDao,
    ChapterDao? chapterDao,
    BookmarkDao? bookmarkDao,
    HighlightDao? highlightDao,
  }) : _bookDao = bookDao ?? getIt<BookDao>(),
       _chapterDao = chapterDao ?? getIt<ChapterDao>(),
       _bookmarkDao = bookmarkDao ?? getIt<BookmarkDao>(),
       _highlightDao = highlightDao ?? getIt<HighlightDao>();

  final BookDao _bookDao;
  final ChapterDao _chapterDao;
  final BookmarkDao _bookmarkDao;
  final HighlightDao _highlightDao;

  /// 把 [target] 這本書的目錄排成 [reversed]（true 是反轉）。照資料庫裡
  /// 最新的一筆改；還沒存過（從搜尋打開、沒加入書架）時存進 [target]。已經
  /// 是這樣時什麼都不動、傳回 null；否則傳回寫好的書與新的目錄。
  Future<({Book book, List<BookChapter> chapters})?> setReversed(
    Book target,
    bool reversed,
  ) => _bookDao.transaction(() async {
    final bookUrl = target.bookUrl;
    final book = await _bookDao.getByUrl(bookUrl) ?? target.copyWith();
    if ((book.readConfig?.reverseToc ?? false) == reversed) return null;
    final oldToc = await _chapterDao.getByBook(bookUrl);
    final chapters = reversedToc(oldToc);
    book.realignProgress(chapters, oldToc: oldToc);
    // 複本：[target] 的閱讀設定可能是閱讀器手上那一份，寫不成時不能先變。
    book.readConfig = ReadConfig.fromJson(
      (book.readConfig ?? ReadConfig()).toJson(),
    )..reverseToc = reversed;
    if (chapters.isNotEmpty) {
      await _chapterDao.replaceByBook(bookUrl, chapters);
      await _bookmarkDao.reverseChapters(
        bookName: book.name,
        bookAuthor: book.author,
        chapterCount: chapters.length,
      );
      await _highlightDao.reverseChapters(
        bookName: book.name,
        bookAuthor: book.author,
        chapterCount: chapters.length,
      );
    }
    await _bookDao.writeFields(
      book,
      BooksCompanion(
        chapterIndex: Value(book.chapterIndex),
        durChapterTitle: Value(book.durChapterTitle),
        charOffset: Value(book.charOffset),
        visualOffsetPx: Value(book.visualOffsetPx),
        readerAnchorJson: Value(book.readerAnchorJson),
        readConfig: Value(book.readConfig),
      ),
    );
    return (book: book, chapters: chapters);
  });
}

/// [toc] 翻過來、照新的順序重新編號（複本，[toc] 不動）。
List<BookChapter> reversedToc(List<BookChapter> toc) => [
  for (final (i, chapter) in toc.reversed.indexed) chapter.copyWith(index: i),
];
