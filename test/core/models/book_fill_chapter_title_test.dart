import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';

void main() {
  final toc = [
    for (var i = 0; i < 3; i++)
      BookChapter(url: 'c$i', title: '第${i + 1}章', bookUrl: 'b', index: i),
  ];

  test('還沒讀過的書照目錄記下目前那一章的章名', () {
    final book = Book(bookUrl: 'b', chapterIndex: 1)..fillChapterTitle(toc);
    expect(book.durChapterTitle, '第2章');
  });

  test('讀的時候寫下的章名不動', () {
    final book = Book(bookUrl: 'b', chapterIndex: 1, durChapterTitle: '舊章名')
      ..fillChapterTitle(toc);
    expect(book.durChapterTitle, '舊章名');
  });

  test('目錄裡沒有目前那一章時不寫', () {
    final book = Book(bookUrl: 'b', chapterIndex: 5)..fillChapterTitle(toc);
    expect(book.durChapterTitle, isNull);
  });
}
