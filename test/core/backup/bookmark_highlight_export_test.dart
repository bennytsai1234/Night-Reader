import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/backup/bookmark_highlight_export.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/core/models/reading/bookmark.dart';
import 'package:night_reader/core/models/reading/highlight.dart';

void main() {
  BookmarkHighlightExportItem item(
    int chapter,
    int offset,
    String title,
    String text, {
    String note = '',
  }) => (
    chapter: chapter,
    charOffset: offset,
    chapterTitle: title,
    text: text,
    note: note,
  );

  Highlight paint(String chapter, String quote, {int offset = 0}) => Highlight(
    id: 0,
    bookName: '夜雨聽書',
    chapterTitle: chapter,
    charOffset: offset,
    quote: quote,
  );

  Bookmark mark(
    String chapter,
    String excerpt, {
    int offset = 0,
    int chapterIndex = 0,
  }) => Bookmark(
    id: 0,
    bookName: '夜雨聽書',
    chapterIndex: chapterIndex,
    chapterTitle: chapter,
    charOffset: offset,
    excerpt: excerpt,
  );

  test('bookmarks and highlights share one heading per book and chapter, in '
      'reading order; each is a quote and a note follows its quote', () {
    final markdown = bookmarksAndHighlightsToMarkdown([
      (
        bookName: '夜雨聽書',
        bookAuthor: '沈知秋',
        items: [
          item(1, 5, '第二章', '他快步走過長街。'),
          item(1, 1, '第二章', '松煙墨'),
          item(0, 10, '第一章', '雨聲'),
          item(0, 2, '第一章', '燈下\n字句', note: '  想起外婆的墨盒 '),
          item(0, 20, '第一章', '夜色'),
        ],
      ),
      (bookName: '空的書', bookAuthor: '', items: const []),
      (bookName: '松煙墨', bookAuthor: '', items: [item(0, 0, '', '墨香')]),
    ]);
    expect(markdown, '''
# 夜雨聽書

沈知秋

## 第一章

> 燈下
> 字句

想起外婆的墨盒

> 雨聲

> 夜色

## 第二章

> 松煙墨

> 他快步走過長街。

# 松煙墨

## （沒有章名）

> 墨香
''');
  });

  test('bookmarks and highlights are lined up with this phone\'s chapters', () {
    final toc = [
      BookChapter(url: '/c/0', title: '第一章'),
      BookChapter(url: '/c/1', title: '第二章'),
      BookChapter(url: '/c/2', title: '第三章'),
    ];
    final items = bookmarkHighlightExportItems(
      bookmarks: [mark('第三章', '書籤那一句', offset: 5, chapterIndex: 9)],
      highlights: [paint('第一章', '標註的字', offset: 3)],
      toc: toc,
    );

    expect([for (final item in items) item.chapter], [0, 2]);
    expect(items.first.text, '標註的字');
    expect(items.last.text, '書籤那一句');
  });
}
