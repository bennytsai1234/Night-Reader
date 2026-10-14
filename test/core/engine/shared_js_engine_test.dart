import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/web_book/book_list_parser.dart';
import 'package:night_reader/core/engine/web_book/chapter_list_parser.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';

import '../../test_helper.dart';

/// 清單逐項的規則借用外層規則的 JS 引擎；每一項的 JS 仍要看到自己那一項：
/// `java` 取的是這一項的元素，`result`、`book` 也是這一項的。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupTestDI();

  test('each chapter rule sees its own element through java', () async {
    final source = BookSource.fromJson({
      'bookSourceName': '共用引擎',
      'bookSourceUrl': 'https://js.test',
      'ruleToc': {
        'chapterList': 'class.list@a',
        'chapterName': 'a@text@js:result + "|" + java.getString("a@href")',
        'chapterUrl': 'a@href',
      },
    });
    final book = Book(
      bookUrl: 'https://js.test/book/',
      origin: 'https://js.test',
      name: '共用引擎',
      tocUrl: 'https://js.test/book/',
    );
    const html =
        '<html><body><div class="list">'
        '<a href="/book/1.html">第一章</a>'
        '<a href="/book/2.html">第二章</a>'
        '<a href="/book/3.html">第三章</a>'
        '</div></body></html>';

    final result = await ChapterListParser.parse(
      source: source,
      book: book,
      body: html,
      baseUrl: book.tocUrl,
    );

    expect(result.chapters.map((c) => c.title), [
      '第一章|/book/1.html',
      '第二章|/book/2.html',
      '第三章|/book/3.html',
    ]);
  });

  test('a var declared by one chapter rule does not reach the next', () async {
    // Legado 每次執行 JS 都是新的作用域；「還沒定義才算」的寫法每章都要
    // 重新算，不能沿用前一章留下的值。
    final source = BookSource.fromJson({
      'bookSourceName': '共用引擎',
      'bookSourceUrl': 'https://js.test',
      'ruleToc': {
        'chapterList': 'class.list@a',
        'chapterName': 'a@text@js:if (typeof seen === "undefined") { var seen = result; } seen',
        'chapterUrl': 'a@href',
      },
    });
    final book = Book(
      bookUrl: 'https://js.test/book/',
      origin: 'https://js.test',
      name: '共用引擎',
      tocUrl: 'https://js.test/book/',
    );
    const html =
        '<html><body><div class="list">'
        '<a href="/book/1.html">第一章</a>'
        '<a href="/book/2.html">第二章</a>'
        '</div></body></html>';

    final result = await ChapterListParser.parse(
      source: source,
      book: book,
      body: html,
      baseUrl: book.tocUrl,
    );

    expect(result.chapters.map((c) => c.title), ['第一章', '第二章']);
  });

  test('each search result rule sees its own item', () async {
    final source = BookSource.fromJson({
      'bookSourceName': '共用引擎',
      'bookSourceUrl': 'https://js.test',
      'searchUrl': '/s?q={{key}}',
      'ruleSearch': {
        'bookList': 'class.item',
        'name': 'class.name@text@js:result.trim() + "·" + book.origin',
        'author': 'class.author@text@js:java.getString("class.name@text")',
        'bookUrl': 'class.name@href',
      },
    });
    const html =
        '<html><body>'
        '<div class="item"><a class="name" href="/b/1"> 甲書 </a>'
        '<span class="author">甲</span></div>'
        '<div class="item"><a class="name" href="/b/2"> 乙書 </a>'
        '<span class="author">乙</span></div>'
        '</body></html>';

    final books = await BookListParser.parse(
      source: source,
      body: html,
      baseUrl: 'https://js.test/s?q=x',
      isSearch: true,
    );

    expect(books.map((b) => b.name), [
      '甲書·https://js.test',
      '乙書·https://js.test',
    ]);
    expect(books.map((b) => b.author?.trim()), ['甲書', '乙書']);
  });
}
