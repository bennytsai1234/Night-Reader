import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/web_book/book_list_parser.dart';
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

  BookSource source(String pattern) => BookSource.fromJson({
    'bookSourceName': '詳情頁判斷',
    'bookSourceUrl': 'https://s.example',
    'bookUrlPattern': pattern,
    'ruleSearch': {
      'bookList': 'class.item',
      'name': 'class.name@text',
      'bookUrl': 'class.name@href',
    },
    'ruleBookInfo': {'name': 'class.title@text'},
  });

  Future<List<String>> search(String pattern, String baseUrl) async {
    final books = await BookListParser.parse(
      source: source(pattern),
      body: html,
      baseUrl: baseUrl,
      isSearch: true,
    );
    return books.map((b) => b.name).toList();
  }

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
}
