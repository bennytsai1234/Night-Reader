import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/web_book/book_info_parser.dart';
import 'package:night_reader/core/engine/web_book/book_list_parser.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';

import '../../test_helper.dart';

/// `java.getElement` 與詳情頁的 `init`：CSS、XPath 規則同 Legado 交回找到的
/// 一整組元素（Jsoup 的 Elements），不是只有第一個。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupTestDI();

  const html =
      '<html><body><ol class="list">'
      '<li><a class="t" href="/b/1">甲書</a></li>'
      '<li><a class="t" href="/b/2">乙書</a></li>'
      '</ol></body></html>';

  Future<List<String>> names(String bookList, {String body = html}) async {
    final source = BookSource.fromJson({
      'bookSourceName': '一組元素',
      'bookSourceUrl': 'https://ge.test',
      'searchUrl': '/s?q={{key}}',
      'ruleSearch': {
        'bookList': bookList,
        'name': 'class.t@text',
        'bookUrl': 'class.t@href',
      },
    });
    final books = await BookListParser.parse(
      source: source,
      body: body,
      baseUrl: 'https://ge.test/s?q=x',
      isSearch: true,
    );
    return [for (final book in books) book.name];
  }

  test('java.getElement 交回一整組，讀得到 length', () async {
    // 哔哩轻小说的寫法：先看有沒有找到，沒有才改用別的方法。
    expect(
      await names(
        "@js:var c = java.getElement('class.list@tag.li');\n"
        "if (!c.length) throw 'none';\nc",
      ),
      ['甲書', '乙書'],
    );
    expect(
      await names(
        "@js:var c = java.getElement('class.none@tag.li');\n"
        "c.length === 0 ? java.getElement('class.list@tag.li') : c",
      ),
      ['甲書', '乙書'],
    );
  });

  test('詳情頁 init 找到多個元素時，後面的規則看得到全部', () async {
    final source = BookSource.fromJson({
      'bookSourceName': '一組元素',
      'bookSourceUrl': 'https://ge.test',
      'ruleBookInfo': {
        'init': 'class.list@tag.li',
        'name': 'class.t.1@text',
        'author': 'class.t.0@text',
      },
    });
    final book = await BookInfoParser.parse(
      source: source,
      book: Book(bookUrl: 'https://ge.test/b/1', origin: 'https://ge.test'),
      body: html,
      baseUrl: 'https://ge.test/b/1',
    );
    expect(book.name, '乙書');
    expect(book.author, '甲書');
  });

  test('詳情頁 init 用 XPath 找到多個節點時照網頁讀，不當成 JSON', () async {
    final source = BookSource.fromJson({
      'bookSourceName': '一組元素',
      'bookSourceUrl': 'https://ge.test',
      'ruleBookInfo': {
        'init': '//ol/li',
        'name': 'class.t.1@text',
        'author': '//li[1]/a/text()',
      },
    });
    final book = await BookInfoParser.parse(
      source: source,
      book: Book(bookUrl: 'https://ge.test/b/1', origin: 'https://ge.test'),
      body: html,
      baseUrl: 'https://ge.test/b/1',
    );
    expect(book.name, '乙書');
    expect(book.author, '甲書');
  });
}
