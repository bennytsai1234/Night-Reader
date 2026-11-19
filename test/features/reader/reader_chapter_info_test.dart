import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/features/reader/screen/reader_chapter_info.dart';
import 'package:night_reader/features/reader/screen/reader_page_shell.dart';
import 'package:night_reader/features/reader/session/reader_open_target.dart';

/// 開書前（Runtime 還沒建好）的章節資訊。
void main() {
  final book = Book(
    bookUrl: 'https://x/book',
    origin: 'https://x',
    name: '夜雨聽書',
    chapterIndex: 2,
    durChapterTitle: '第三章 雨夜',
    totalChapterNum: 120,
  );
  BookChapter chapter(int index) => BookChapter(
    url: 'https://x/c$index',
    title: '第 $index 章',
    bookUrl: book.bookUrl,
    index: index,
  );
  ReaderChapterInfo info({
    List<BookChapter> chapters = const [],
    ReaderOpenTarget? openTarget,
  }) => ReaderChapterInfo(
    book: book,
    initialChapters: chapters,
    openTarget: openTarget,
    runtime: () => null,
    chineseConvert: () => 0,
  );

  test('目錄還沒載入：閱讀紀錄那一章用紀錄的章名，別章是空的', () {
    expect(info().chapterTitleAt(2), '第三章 雨夜');
    expect(info().chapterTitleAt(3), '');
  });

  test('有開書前的目錄就照目錄的章名與網址', () {
    final withToc = info(chapters: [for (var i = 0; i < 5; i++) chapter(i)]);
    expect(withToc.chapterTitleAt(3), '第 3 章');
    expect(withToc.chapterUrlAt(3), 'https://x/c3');
    expect(withToc.chapterAt(3)?.url, 'https://x/c3');
    expect(withToc.chapterUrlAt(9), '');
    expect(withToc.chapterAt(9), isNull);
    expect(withToc.chapterAt(-1), isNull);
    expect(withToc.chapterUrlAt(-1), '');
  });

  test('還沒有 Runtime：頁首頁尾畫骨架，描述要開的那一章', () {
    expect(info().infoStateOf(null), ReaderInfoState.loading);
    final target = info().infoTargetOf(null);
    expect(target.chapterIndex, 2, reason: '書的閱讀紀錄');
    expect(target.chapterCount, 120, reason: '目錄還沒載入時章數照書的紀錄');
    expect(target.title, '第三章 雨夜');
  });

  test('指定了開哪裡就描述那一章', () {
    final opened = info(
      chapters: [for (var i = 0; i < 8; i++) chapter(i)],
      openTarget: ReaderOpenTarget.chapterStart(5),
    );
    expect(opened.openChapterIndex, 5);
    final target = opened.infoTargetOf(null);
    expect(target.chapterIndex, 5);
    expect(target.chapterCount, 8);
    expect(target.title, '第 5 章');
  });

  test('還沒有 Runtime 時目前章是 0', () {
    expect(info().currentChapterIndex(null), 0);
  });
}
