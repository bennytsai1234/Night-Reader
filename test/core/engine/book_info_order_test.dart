import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/web_book/book_info_parser.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';

import '../../test_helper.dart';

/// 詳情頁照 Legado 的順序算（書名、作者、分類、字數、最新章節、簡介、封面、
/// 目錄網址），每一項算完就寫到書上，後面的規則 JS 讀得到。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupTestDI();

  test('目錄網址的規則讀得到這一頁剛算出來的簡介與書名', () async {
    // 蓝海搜书：簡介裡寫「当前来源【0】」，目錄網址從 book.intro 取序號。
    final source = BookSource.fromJson({
      'bookSourceName': '順序',
      'bookSourceUrl': 'https://order.test',
      'ruleBookInfo': {
        'name': '.title@text',
        'intro': '.intro@text@js:result + "\\n当前来源【2】"',
        'tocUrl':
            '@js:var n = String(book.intro).match(/来源【(\\d+)】/)[1];\n'
            '"/toc/" + n + "/" + encodeURIComponent(book.name)',
      },
    });
    final original = Book(
      bookUrl: 'https://order.test/b/1',
      origin: 'https://order.test',
      name: '搜尋時的書名',
    );
    final book = await BookInfoParser.parse(
      source: source,
      book: original,
      body:
          '<html><body><h1 class="title">詳情的書名</h1>'
          '<div class="intro">簡介</div></body></html>',
      baseUrl: 'https://order.test/b/1',
    );

    expect(book.intro, '簡介\n当前来源【2】');
    expect(
      book.tocUrl,
      'https://order.test/toc/2/${Uri.encodeComponent('詳情的書名')}',
    );
    // 傳進來的書不被改到。
    expect(original.intro, isNull);
    expect(original.name, '搜尋時的書名');
  });

  test('詳情頁的書名、作者拿掉「作者：」「著」這類字樣，同搜尋結果', () async {
    final source = BookSource.fromJson({
      'bookSourceName': '字樣',
      'bookSourceUrl': 'https://label.test',
      'ruleBookInfo': {'name': '.title@text', 'author': '.author@text'},
    });
    final book = await BookInfoParser.parse(
      source: source,
      book: Book(
        bookUrl: 'https://label.test/b/1',
        origin: 'https://label.test',
        name: '夜航',
        author: '某人',
      ),
      body:
          '<html><body><h1 class="title">夜航 作者：某人</h1>'
          '<p class="author">作者：某人</p></body></html>',
      baseUrl: 'https://label.test/b/1',
    );

    expect(book.name, '夜航');
    expect(book.author, '某人');
  });

  test('規則改閱讀設定時只改交回的書', () async {
    final source = BookSource.fromJson({
      'bookSourceName': '順序',
      'bookSourceUrl': 'https://order.test',
      'ruleBookInfo': {
        'name': '@js:book.setReverseToc(true); "書名"',
        'tocUrl': '/toc',
      },
    });
    final original = Book(
      bookUrl: 'https://order.test/b/1',
      origin: 'https://order.test',
      readConfig: ReadConfig(),
    );
    final book = await BookInfoParser.parse(
      source: source,
      book: original,
      body: '<html></html>',
      baseUrl: 'https://order.test/b/1',
    );
    expect(book.name, '書名');
    expect(original.readConfig?.reverseToc, isFalse);
  });
}
