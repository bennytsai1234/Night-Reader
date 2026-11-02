import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/web_book/book_info_parser.dart';
import 'package:night_reader/core/engine/web_book/content_parser.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/source/lenient_json.dart';

import '../../test_helper.dart';

/// `@put:{…}` 存變數：同 Legado 照 Gson 讀，標準 JSON 與寬鬆寫法都收。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupTestDI();

  Future<Book> detail(String nameRule) => BookInfoParser.parse(
    source: BookSource.fromJson({
      'bookSourceName': '存變數',
      'bookSourceUrl': 'https://put.test',
      'ruleBookInfo': {'init': 'data.book', 'name': nameRule},
    }),
    book: Book(bookUrl: 'https://put.test/b', origin: 'https://put.test'),
    body: '{"data":{"book":{"id":1885648,"title":"書名"}}}',
    baseUrl: 'https://put.test/b',
  );

  test('鍵和值沒加引號（七猫小说的 @put:{bid:id}）也存得到', () async {
    final book = await detail('title@put:{bid:id}');
    expect(book.name, '書名');
    expect(book.getVariable('bid'), '1885648');
  });

  test('正文的規則讀得到書上存的變數（章節沒有這個變數時）', () async {
    final book = await detail('title@put:{bid:id}');
    final result = await ContentParser.parse(
      source: BookSource.fromJson({
        'bookSourceName': '存變數',
        'bookSourceUrl': 'https://put.test',
        'ruleContent': {'content': '@js:"書號 " + java.get("bid")'},
      }),
      book: book,
      chapter: BookChapter(url: 'https://put.test/c/1', title: '第一章'),
      body: '<p>x</p>',
      baseUrl: 'https://put.test/c/1',
    );
    expect(result.content, contains('書號 1885648'));
  });

  test('數字照原文讀（同 Gson 讀進文字）', () {
    expect(
      decodeLenientJson(
        '{bid:007, v:1.50, t:1e3, ok:true}',
        numbersAsText: true,
      ),
      {'bid': '007', 'v': '1.50', 't': '1e3', 'ok': true},
    );
    expect(decodeLenientJson('{"v":1.50}', numbersAsText: true), {'v': '1.50'});
    // 沒指定時照舊讀成數字。
    expect(decodeLenientJson('{v:1.50}'), {'v': 1.5});
  });

  test('標準 JSON 照舊', () async {
    final book = await detail(r'title@put:{"bid":"$.id"}');
    expect(book.getVariable('bid'), '1885648');
  });
}
