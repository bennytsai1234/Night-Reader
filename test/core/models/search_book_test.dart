import 'package:flutter_test/flutter_test.dart';
import 'package:reader/core/models/search_book.dart';

void main() {
  test('sourceLabels 會保留各來源的名稱', () {
    final book = SearchBook(
      bookUrl: 'https://example.com/book/1',
      name: '測試書',
      author: '作者甲',
      origin: 'source://a',
      originName: '書源 A',
    );

    book.addOrigin('source://b', name: '書源 B');
    book.addOrigin('source://c');

    expect(
      book.sourceLabels,
      containsAll(<String>['書源 A', '書源 B', 'source://c']),
    );
  });

  test(
    'toBook preserves parsed metadata and variables needed by later stages',
    () {
      final searchBook = SearchBook(
        bookUrl: 'https://example.com/book/1',
        name: '測試書',
        author: '作者甲',
        kind: '玄幻',
        wordCount: '12萬字',
        latestChapterTitle: '第一章',
        origin: 'source://a',
        originName: '書源 A',
        originOrder: 7,
        variable: '{"token":"abc"}',
      );

      final book = searchBook.toBook();

      expect(book.kind, '玄幻');
      expect(book.wordCount, '12萬字');
      expect(book.latestChapterTitle, '第一章');
      expect(book.originOrder, 7);
      expect(book.getVariable('token'), 'abc');
    },
  );
}
