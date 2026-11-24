import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/analyze_rule.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/search/search_book.dart';
import 'package:night_reader/core/models/source/book_source.dart';

import '../../test_helper.dart';

/// `@get`／`@put` 與 `java.get`／`java.put` 找變數的地方照 Legado
/// `AnalyzeRule.get`／`put`：`bookName` 是書名、`title` 是章名，其他依序找
/// 章節、書、書源；沒有章節也沒有書時存進書源。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupTestDI();

  BookSource source() => BookSource(bookSourceUrl: 'https://scope.test');

  test('@get:{bookName} 與 java.get("bookName") 是這本書的書名', () {
    final book = Book(bookUrl: 'https://scope.test/b', name: '斗羅大陸');
    final rule = AnalyzeRule(
      source: source(),
      ruleData: book,
    ).setContent('<p>x</p>', baseUrl: 'https://scope.test/b');
    expect(rule.getString('@get:{bookName}'), '斗羅大陸');
    expect(rule.getString('@js:java.get("bookName")'), '斗羅大陸');
  });

  test('搜尋結果也算書', () {
    final book = SearchBook(
      bookUrl: 'https://scope.test/b',
      name: '雪中悍刀行',
      origin: 'https://scope.test',
    );
    final rule = AnalyzeRule(
      source: source(),
      ruleData: book,
    ).setContent('<p>x</p>', baseUrl: 'https://scope.test/b');
    expect(rule.getString('@get:{bookName}'), '雪中悍刀行');
  });

  test('沒有書的地方 @put 存進書源，之後的規則讀得到', () {
    final first = AnalyzeRule(source: source())
        .setContent('{"token":"abc"}', baseUrl: 'https://scope.test/');
    first.getString(r'@put:{tk:$.token}');
    final later = AnalyzeRule(source: source())
        .setContent('<p>x</p>', baseUrl: 'https://scope.test/');
    expect(later.getString('@get:{tk}'), 'abc');
  });

  test('page、key 這些名字不攔下，拿到的是存的值', () {
    final book = Book(bookUrl: 'https://scope.test/b', name: '書');
    final rule = AnalyzeRule(
      source: source(),
      ruleData: book,
    ).setContent('{"p":"7"}', baseUrl: 'https://scope.test/b');
    rule.getString(r'@put:{page:$.p}');
    expect(rule.getString('@get:{page}'), '7');
  });
}
