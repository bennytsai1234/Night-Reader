import 'package:flutter_test/flutter_test.dart';
import 'package:reader/core/models/search_book.dart';
import 'package:reader/features/search/search_model.dart';

void main() {
  group('matchesPrecisionSearch', () {
    SearchBook buildBook({required String name, String? author}) {
      return SearchBook(
        bookUrl: 'https://example.com/book',
        name: name,
        author: author,
        origin: 'https://example.com',
        originName: '測試書源',
      );
    }

    test('matches normalized exact title', () {
      final book = buildBook(name: ' 我的 徒弟 ', author: '貓膩');

      expect(matchesPrecisionSearch(book, '我的徒弟'), isTrue);
    });

    test('matches normalized exact author', () {
      final book = buildBook(name: '雪中悍刀行', author: '烽火戲諸侯');

      expect(matchesPrecisionSearch(book, ' 烽火戲諸侯 '), isTrue);
    });

    test('requires exact equality and rejects blank keywords', () {
      final book = buildBook(name: '大奉打更人', author: '賣報小郎君');

      expect(matchesPrecisionSearch(book, '大奉'), isFalse);
      expect(matchesPrecisionSearch(book, '   '), isFalse);
    });

    test('relevance rank separates exact, contains, and other matches', () {
      final exact = buildBook(name: '劍來', author: '烽火戲諸侯');
      final contains = buildBook(name: '劍來番外', author: '烽火戲諸侯');
      final other = buildBook(name: '雪中悍刀行', author: '烽火戲諸侯');

      expect(searchRelevanceRank(exact, '劍來'), 0);
      expect(searchRelevanceRank(contains, '劍來'), 1);
      expect(searchRelevanceRank(other, '劍來'), 2);
    });
  });
}
