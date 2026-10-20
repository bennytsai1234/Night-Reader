import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/web_book/book_info_parser.dart';
import 'package:night_reader/core/engine/web_book/book_list_parser.dart';
import 'package:night_reader/core/models/book_source.dart';

import '../../../test_helper.dart';

/// 發現清單的封面與字數：規則有給的都要帶到清單上（相對網址補成完整網址），
/// 發現規則沒有清單、改用搜尋規則時也一樣。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupTestDI();

  const html =
      '<html><body>'
      '<div class="item"><a class="name" href="/book/1">甲書</a>'
      '<span class="author">甲</span><img src="/cover/1.jpg">'
      '<span class="words">123456</span></div>'
      '<div class="item"><a class="name" href="/book/2">乙書</a>'
      '<span class="author">乙</span><img src="//img.example/2.jpg">'
      '<span class="words">2.5萬字</span></div>'
      '</body></html>';

  const listRule = {
    'bookList': 'class.item',
    'name': 'class.name@text',
    'author': 'class.author@text',
    'bookUrl': 'class.name@href',
    'coverUrl': 'img@src',
    'wordCount': 'class.words@text',
  };

  Future<void> expectFields(BookSource source) async {
    final books = await BookListParser.parse(
      source: source,
      body: html,
      baseUrl: 'https://s.example/category/1',
      isSearch: false,
    );
    expect(books.map((b) => b.coverUrl), [
      'https://s.example/cover/1.jpg',
      'https://img.example/2.jpg',
    ]);
    expect(books.map((b) => b.wordCount), ['12.3萬字', '2.5萬字']);
  }

  test('the explore rule brings covers and word counts', () async {
    await expectFields(
      BookSource.fromJson({
        'bookSourceName': '發現',
        'bookSourceUrl': 'https://s.example',
        'ruleExplore': listRule,
      }),
    );
  });

  test(
    'an explore rule without a list falls back to the search rule',
    () async {
      await expectFields(
        BookSource.fromJson({
          'bookSourceName': '發現',
          'bookSourceUrl': 'https://s.example',
          'ruleExplore': {'bookList': ''},
          'ruleSearch': listRule,
        }),
      );
    },
  );

  test('a cover rule that matches nothing leaves the cover empty', () async {
    // getString 帶 isUrl 時沒抓到會回傳頁面網址；封面若變成這個網址，清單
    // 上載不出來，書籍詳情抓到的封面也會被它蓋掉。
    final source = BookSource.fromJson({
      'bookSourceName': '發現',
      'bookSourceUrl': 'https://s.example',
      'ruleExplore': {...listRule, 'coverUrl': 'img.lazy@data-src'},
      'ruleBookInfo': {'name': 'h1@text', 'coverUrl': 'img.lazy@data-src'},
    });
    final books = await BookListParser.parse(
      source: source,
      body: html,
      baseUrl: 'https://s.example/category/1',
      isSearch: false,
    );
    expect(books.map((b) => b.coverUrl), ['', '']);

    final info = await BookInfoParser.parse(
      source: source,
      book: books.first.toBook()..coverUrl = 'https://s.example/cover/1.jpg',
      body: '<html><body><h1>甲書</h1></body></html>',
      baseUrl: 'https://s.example/book/1',
    );
    expect(info.coverUrl, 'https://s.example/cover/1.jpg');
  });

  test(
    'an explore list that finds nothing retries with the search rule',
    () async {
      await expectFields(
        BookSource.fromJson({
          'bookSourceName': '發現',
          'bookSourceUrl': 'https://s.example',
          'ruleExplore': {...listRule, 'bookList': 'class.missing'},
          'ruleSearch': listRule,
        }),
      );
    },
  );
}
