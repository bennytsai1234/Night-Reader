import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/services/chinese_utils.dart';

/// 用書源最新的目錄換掉一本書已存的目錄（檢查更新用）。
class BookTocReplacer {
  BookTocReplacer({required this.chapterDao, this.contentDao});

  final ChapterDao chapterDao;
  final ReaderChapterContentDao? contentDao;

  /// 在交易內呼叫，[book] 要是資料庫裡最新的一筆。寫入新目錄，並把 [book]
  /// 的閱讀進度依章節網址對到新目錄，由呼叫端寫回。
  ///
  /// 書源拿掉的章節移出目錄，但已下載或正在讀的留下來，插回原本的位置：
  /// 網站壞掉時常只回一部分目錄（例如側欄的最新章節），照單全收會讓已下載
  /// 的章節點不到、進度跑掉。新目錄裡有同名章節的不留，那是書源換了網址
  /// （例如整站搬家）。書源回傳空目錄時丟 [StateError]，什麼都不寫。
  Future<({List<BookChapter> chapters, bool progressMoved})> replace(
    Book book,
    List<BookChapter> fetched,
  ) async {
    if (fetched.isEmpty) throw StateError('書源回傳的目錄是空的');
    final oldToc = await chapterDao.getByBook(book.bookUrl);
    final storedUrls =
        await contentDao?.getStoredChapterUrls(
          origin: book.origin,
          bookUrl: book.bookUrl,
        ) ??
        const <String>{};
    final chapters = keepDroppedChapters(
      oldToc: oldToc,
      fetched: fetched,
      keep: (chapter) =>
          book.durChapterTime > 0 && chapter.index == book.chapterIndex ||
          storedUrls.contains(chapter.url),
    );
    for (var i = 0; i < chapters.length; i++) {
      chapters[i].index = i;
      chapters[i].bookUrl = book.bookUrl;
    }
    final progressMoved = book.realignProgress(chapters, oldToc: oldToc);
    // 目錄沒變就不重寫：書架檢查每本書都會走這裡，大多數時候目錄一樣，
    // 整份刪掉再寫回要組上千筆寫入。
    if (!_sameAsStored(oldToc, chapters)) {
      await chapterDao.replaceByBook(book.bookUrl, chapters);
    }
    return (chapters: chapters, progressMoved: progressMoved);
  }
}

/// [chapters] 寫進資料庫後會和 [stored] 一模一樣。比對的欄位與章節表寫入的
/// 欄位相同（`BookChapterToInsertable`），章節表加欄位時這裡要一起加。
bool _sameAsStored(List<BookChapter> stored, List<BookChapter> chapters) {
  if (stored.length != chapters.length) return false;
  for (var i = 0; i < stored.length; i++) {
    final a = stored[i];
    final b = chapters[i];
    if (a.url != b.url ||
        a.title != b.title ||
        a.isVolume != b.isVolume ||
        a.baseUrl != b.baseUrl ||
        a.bookUrl != b.bookUrl ||
        a.index != b.index ||
        a.isVip != b.isVip ||
        a.isPay != b.isPay ||
        a.resourceUrl != b.resourceUrl ||
        a.tag != b.tag ||
        a.wordCount != b.wordCount ||
        a.start != b.start ||
        a.end != b.end ||
        a.startFragmentId != b.startFragmentId ||
        a.endFragmentId != b.endFragmentId ||
        a.variable != b.variable) {
      return false;
    }
  }
  return true;
}

/// [fetched] 加上 [oldToc] 裡書源拿掉、但 [keep] 要留的章節。留下的章節接在
/// 舊目錄裡它前面最近一個還在的章節後面；前面都不在了就放最前面。標題與
/// [fetched] 裡某一章相同（繁簡視為相同）的不留。
List<BookChapter> keepDroppedChapters({
  required List<BookChapter> oldToc,
  required List<BookChapter> fetched,
  required bool Function(BookChapter chapter) keep,
}) {
  final fetchedUrls = {for (final chapter in fetched) chapter.url};
  // 只有真的遇到書源拿掉、又要留的章節才轉換整份新目錄的章名：一般檢查
  // 更新沒有章節被拿掉，不必把上千個章名都轉一次。
  late final fetchedTitles = {
    for (final chapter in fetched) ChineseUtils.t2s(chapter.title),
  };
  final front = <BookChapter>[];
  final after = <String, List<BookChapter>>{};
  String? lastKeptUrl;
  for (final chapter in oldToc) {
    if (fetchedUrls.contains(chapter.url)) {
      lastKeptUrl = chapter.url;
      continue;
    }
    if (!keep(chapter) ||
        fetchedTitles.contains(ChineseUtils.t2s(chapter.title))) {
      continue;
    }
    // 複製一份：呼叫端會重編序號，[oldToc] 要留著對進度。
    final anchor = lastKeptUrl;
    (anchor == null ? front : after.putIfAbsent(anchor, () => [])).add(
      chapter.copyWith(),
    );
  }
  if (front.isEmpty && after.isEmpty) return fetched;
  return [
    ...front,
    for (final chapter in fetched) ...[chapter, ...?after[chapter.url]],
  ];
}
