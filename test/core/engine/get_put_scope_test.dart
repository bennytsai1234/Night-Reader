import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/analyze_rule.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
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

  final skip = quickJsUnavailableReason();

  test('java.put 有章節時只存在章節，不寫進書源', () {
    final shared = source();
    final chapter = BookChapter(url: 'https://scope.test/c/1', title: '第一章');
    final rule =
        AnalyzeRule(
              source: shared,
              ruleData: Book(bookUrl: 'https://scope.test/b', name: '斗羅大陸'),
            )
            .setChapter(chapter)
            .setContent('<p>x</p>', baseUrl: 'https://scope.test/c/1');
    addTearDown(rule.dispose);

    expect(rule.evalJS("java.put('chapterOnlyTk', '章節值')", null), '章節值');
    expect(chapter.getVariable('chapterOnlyTk'), '章節值');

    // 同一個書源的下一個地方沒有這個變數：Legado 沒有章節、書、搜尋結果時
    // 才寫書源，java.put 不另外複製一份到書源。
    final other = AnalyzeRule(source: shared)
        .setContent('<p>x</p>', baseUrl: 'https://scope.test/other/1');
    addTearDown(other.dispose);
    expect(other.evalJS("java.get('chapterOnlyTk')", null), '');
    expect(other.getString('@get:{chapterOnlyTk}'), '');
  }, skip: skip);

  test('java.get 還是讀得到 source.put 存的', () {
    final shared = source();
    final first = AnalyzeRule(source: shared)
        .setContent('<p>x</p>', baseUrl: 'https://scope.test/');
    addTearDown(first.dispose);
    first.evalJS("source.put('token', 'abc')", null);

    final later = AnalyzeRule(source: shared)
        .setContent('<p>x</p>', baseUrl: 'https://scope.test/');
    addTearDown(later.dispose);
    expect(later.evalJS("java.get('token')", null), 'abc');
  }, skip: skip);
}
