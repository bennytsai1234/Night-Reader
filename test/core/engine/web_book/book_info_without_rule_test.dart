import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/ai_repair/ai_repair_prompt.dart';
import 'package:night_reader/core/engine/web_book/book_info_parser.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';

import '../../../test_helper.dart';

/// 一篇文章就是一本書的網站（涨姿势）：詳情頁就是目錄頁，也是正文頁。
const _page =
    '<html><head><title>一篇文章</title></head>'
    '<body><h1>一篇文章</h1><p>內文</p></body></html>';

const _bookUrl = 'http://site.test/551908.html';

Future<Book> _parse(BookSource source) => BookInfoParser.parse(
  source: source,
  book: Book(bookUrl: _bookUrl, origin: 'http://site.test', name: '一篇文章'),
  body: _page,
  baseUrl: _bookUrl,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupTestDI();

  // 同 Legado（BookSource.getBookInfoRule 沒有詳情規則時給一份空的，
  // BookInfo.analyzeBookInfo 目錄網址算出空的就用詳情頁網址）。
  test('a source without info rules uses the book page as its toc', () async {
    final book = await _parse(
      BookSource.fromJson({
        'bookSourceName': '涨姿势',
        'bookSourceUrl': 'http://site.test',
      }),
    );

    expect(book.tocUrl, _bookUrl);
  });

  // 2026-11-12 AI 修涨姿势：原本的書源有一份每項都是 null 的詳情規則，AI
  // 一改書源就被當成空欄位拿掉，之後每次試抓都停在「目錄：」空白，AI 為此
  // 繞了 21 輪。沒改任何規則的書源要跟原本走同一條路。
  test(
    'an AI change that touches nothing keeps the toc of the original',
    () async {
      final original = BookSource.fromJson({
        'bookSourceName': '涨姿势',
        'bookSourceUrl': 'http://site.test',
        'ruleBookInfo': '{"init":null,"name":null,"tocUrl":null}',
      });
      final changed = candidateFrom(
        original,
        applyAiChange(sourceForAi(original), (source: null, patch: {})),
      );

      expect((await _parse(changed)).tocUrl, (await _parse(original)).tocUrl);
    },
  );
}
