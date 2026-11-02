import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/highlight.dart';
import 'package:night_reader/core/services/highlight_export.dart';

void main() {
  Highlight paint(String chapter, String quote) =>
      Highlight(id: 0, bookName: '夜雨聽書', chapterTitle: chapter, quote: quote);

  test('one heading per book, highlights of a chapter under its title, each '
      'one a quote with its note below; books with nothing are left out', () {
    final markdown = highlightsToMarkdown([
      (
        bookName: '夜雨聽書',
        bookAuthor: '沈知秋',
        items: [
          paint('第一章', '雨聲'),
          paint('第一章', '燈下\n字句'),
          paint('第二章', '松煙墨').copyWith(note: '  想起外婆的墨盒 '),
        ],
      ),
      (bookName: '空的書', bookAuthor: '', items: const []),
      (bookName: '松煙墨', bookAuthor: '', items: [paint('', '墨香')]),
    ]);
    expect(markdown, '''
# 夜雨聽書

沈知秋

## 第一章

> 雨聲

> 燈下
> 字句

## 第二章

> 松煙墨

想起外婆的墨盒

# 松煙墨

## （沒有章名）

> 墨香
''');
  });
}
