import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/web_book/book_info_parser.dart';
import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';

import '../../../test_helper.dart';

const _page = '''
<div class="info">
  <h1>我的世界</h1><p class="author">wangyouchen</p>
  <p class="type">其他小说</p><span class="status">连载中••</span>
  <a class="toc" href="/list/11475/">目录</a>
</div>
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupTestDI();

  Future<Book> parse(Map<String, dynamic> infoRule) => BookInfoParser.parse(
    source: BookSource.fromJson({
      'bookSourceName': '九一版主',
      'bookSourceUrl': 'https://m.site.test',
      'ruleBookInfo': {
        'name': 'h1@text',
        'author': '.author@text',
        'tocUrl': '.toc@href',
        ...infoRule,
      },
    }),
    book: Book(
      bookUrl: 'https://m.site.test/list/11475.html',
      origin: 'https://m.site.test',
      kind: '搜尋時的分類',
    ),
    body: _page,
    baseUrl: 'https://m.site.test/list/11475.html',
  );

  // 九一版主的分類規則：前一步拿到兩筆文字（列表），JS 卻當成一段文字呼叫
  // replace。Legado 也在這裡出錯，但只空掉分類，詳情頁照常讀完。
  test(
    'a failing kind rule keeps the old kind and the rest of the page',
    () async {
      final book = await parse({
        'kind': '.type@text&&.status@text@js:result.replace(/小说|\\•/g,"")',
        'intro': '.status@text',
      });

      expect(book.name, '我的世界');
      expect(book.author, 'wangyouchen');
      expect(book.tocUrl, 'https://m.site.test/list/11475/');
      expect(book.intro, '连载中••');
      expect(book.kind, '搜尋時的分類');
    },
    skip: quickJsUnavailableReason(),
  );

  test('a word count too long to be one is skipped', () async {
    final book = await parse({'wordCount': '.author@text##.*##${'9' * 400}'});

    expect(book.name, '我的世界');
    expect(book.wordCount, isNull);
  });

  test('a failing name rule still fails the whole page', () async {
    await expectLater(
      parse({'name': '@js:undefinedFunction()'}),
      throwsA(isA<ParsingException>()),
    );
  }, skip: quickJsUnavailableReason());
}
