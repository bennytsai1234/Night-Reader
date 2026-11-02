import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/web_book/chapter_list_parser.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';

import '../../test_helper.dart';

/// 列表用 XPath、每一項的欄位用 CSS（晋江web 的目錄）：XPath 找到的節點
/// 交給 CSS 規則時，同 Legado 直接用裡面的元素。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupTestDI();

  test('XPath 找到的每一項，CSS 規則讀得到文字與連結', () async {
    final source = BookSource.fromJson({
      'bookSourceName': '晋江的寫法',
      'bookSourceUrl': 'https://jj.test',
      'ruleToc': {
        'chapterList':
            "//div[contains(@class, 'b')]/div[@style='padding-left:10px'][1]/a",
        'chapterName': r'text##\[.*\] ?|^(\d+)\. ?(?=第)',
        'chapterUrl': 'href',
      },
    });
    const url = 'https://jj.test/book2/1?whole=1';
    const html =
        '<html><body><div class="b module">'
        '<div style="padding-left:10px">章节列表：<br>'
        '<a href="/book2/1/1"><span>1.</span> <span>[5年前更新]</span> 升旗仪式</a><br>'
        '<a href="/book2/1/2"><span>2.</span> 挑衅</a>'
        '</div></div></body></html>';

    final result = await ChapterListParser.parse(
      source: source,
      book: Book(bookUrl: url, origin: 'https://jj.test', tocUrl: url),
      body: html,
      baseUrl: url,
    );

    expect(result.chapters.map((c) => c.title), ['1. 升旗仪式', '2. 挑衅']);
    expect(result.chapters.map((c) => c.url), [
      'https://jj.test/book2/1/1',
      'https://jj.test/book2/1/2',
    ]);
  });
}
