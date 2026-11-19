import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/web_book/book_list_parser.dart';
import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/core/models/book_source.dart';

import '../../../test_helper.dart';

/// `bookUrlPattern`：Legado `BookList.kt` 用 `baseUrl.matches(regex)`，整個
/// 網址符合才把搜尋結果頁當成詳情頁；只符合網址的一部分（例如 pattern 只寫
/// 網站網址）不算。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupTestDI();

  const html =
      '<html><body><h1 class="title">詳情書名</h1>'
      '<div class="item"><a class="name" href="/book/1">甲書</a></div>'
      '<div class="item"><a class="name" href="/book/2">乙書</a></div>'
      '</body></html>';

  BookSource source(String pattern, {String name = 'class.title@text'}) =>
      BookSource.fromJson({
        'bookSourceName': '詳情頁判斷',
        'bookSourceUrl': 'https://s.example',
        'bookUrlPattern': pattern,
        'ruleSearch': {
          'bookList': 'class.item',
          'name': 'class.name@text',
          'bookUrl': 'class.name@href',
        },
        'ruleBookInfo': {'name': name},
      });

  Future<List<String>> search(
    String pattern,
    String baseUrl, {
    String name = 'class.title@text',
    String body = html,
    bool Function(String name, String author)? filter,
  }) async {
    final books = await BookListParser.parse(
      source: source(pattern, name: name),
      body: body,
      baseUrl: baseUrl,
      isSearch: true,
      filter: filter,
    );
    return books.map((b) => b.name).toList();
  }

  const detail = r'https://s\.example/book/\d+';
  const detailUrl = 'https://s.example/book/9';

  test('a pattern that only matches part of the URL is not a detail page', () {
    // 微风小说：pattern 是搜尋網址的開頭。
    return expectLater(
      search('https://s.example/s/', 'https://s.example/s/?search=%E7%94%B2'),
      completion(['甲書', '乙書']),
    );
  });

  test('a pattern of just the site URL does not match search URLs', () {
    return expectLater(
      search('https://s.example', 'https://s.example/search?q=a'),
      completion(['甲書', '乙書']),
    );
  });

  test('a pattern that matches the whole URL makes it a detail page', () {
    return expectLater(
      search(r'https://s\.example/book/\d+', 'https://s.example/book/9'),
      completion(['詳情書名']),
    );
  });

  test('the alternatives of a pattern are matched as a whole too', () {
    // 三七小说：用 `|` 列出好幾個網站網址。
    return Future.wait([
      expectLater(
        search(
          'https://a.example|https://s.example',
          'https://s.example/search?q=a',
        ),
        completion(['甲書', '乙書']),
      ),
      expectLater(
        search('https://a.example|https://s.example', 'https://s.example'),
        completion(['詳情書名']),
      ),
    ]);
  });

  // 以下照 Legado BookList.kt：對上 bookUrlPattern 就只照詳情頁解析，結果
  // （或錯誤）就是這次搜尋的結果，不回頭把詳情頁當書單解析。

  test('a detail page whose rule fails reports the error', () {
    // 夜讀原本吞掉錯誤、改解析書單，除錯只看到「未獲取到書籍」。
    return expectLater(
      search(detail, detailUrl, name: '@js:JSON.parse("").name'),
      throwsA(isA<ParsingException>()),
    );
  }, skip: quickJsUnavailableReason());

  test('a detail page without a name finds no book', () {
    return expectLater(
      search(detail, detailUrl, name: 'class.none@text'),
      completion(isEmpty),
    );
  });

  test('a detail page that matches the filter is found', () {
    return expectLater(
      search(detail, detailUrl, filter: (name, author) => name == '詳情書名'),
      completion(['詳情書名']),
    );
  });

  // 寫錯的 pattern 包成「整段符合」後，`[` 會吃掉包在外面的字、變成什麼都
  // 對得上；要先認出寫錯，當成不是詳情頁。
  test('a broken pattern is not taken as a detail page', () {
    return expectLater(
      search('[https', 'https://s.example/search?q=a'),
      completion(['甲書', '乙書']),
    );
  });

  test('a detail page is filtered by name and author like a list item', () {
    // 精準搜尋、換源只要書名作者對得上的書。
    return expectLater(
      search(detail, detailUrl, filter: (name, author) => name == '別本書'),
      completion(isEmpty),
    );
  });

  test('an empty list parsed as a detail page is filtered too', () {
    return expectLater(
      search(
        '',
        'https://s.example/search?q=a',
        body: '<html><body><h1 class="title">詳情書名</h1></body></html>',
        filter: (name, author) => name == '別本書',
      ),
      completion(isEmpty),
    );
  });
}
