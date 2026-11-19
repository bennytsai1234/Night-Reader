import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/web_book/book_info_parser.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/source/book_source.dart';

import '../../../test_helper.dart';

/// 詳情頁的簡介照 Legado（BookInfo.analyzeBookInfo）整理成文字：規則取的是
/// 整段 HTML（`#intro@html`）時，標籤換成換行或拿掉，不留在書上。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupTestDI();

  Future<Book> parse(String introRule, String body) => BookInfoParser.parse(
    source: BookSource.fromJson({
      'bookSourceName': '簡介',
      'bookSourceUrl': 'https://intro.test',
      'ruleBookInfo': {'intro': introRule},
    }),
    book: Book(
      bookUrl: 'https://intro.test/b/1',
      origin: 'https://intro.test',
      name: '書名',
    ),
    body: body,
    baseUrl: 'https://intro.test/b/1',
  );

  // 手机看书（sjks88）的詳情頁：`.desc@html`，段落之間是 `<br />`。
  test('an intro taken as HTML keeps no tags', () async {
    final book = await parse(
      '#intro@html',
      '<html><body><div id="intro">'
          '<p>第一段&nbsp;簡介</p><p>第二段<br />&ldquo;第三段&rdquo;</p>'
          '</div></body></html>',
    );

    expect(book.intro, '　　第一段 簡介\n　　第二段\n　　“第三段”');
  });
}
