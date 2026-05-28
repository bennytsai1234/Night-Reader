import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/web_book/chapter_list_parser.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';

import '../../test_helper.dart';

void main() {
  setupTestDI();
  TestWidgetsFlutterBinding.ensureInitialized();
  final quickJsSkip = quickJsUnavailableReason();

  test('ChapterListParser handles sync dynamic json chapter urls', () async {
    final source = BookSource.fromJson({
      'bookSourceUrl': 'DragonQuestQBqqnv',
      'bookSourceName': '測試目錄書源',
      'ruleToc': {
        'chapterList': r'$.rows',
        'chapterName': r'$.serialName',
        'chapterUrl':
            r'https://example.com/content,{"method":"POST","body":{"bookId":"{{baseUrl.match(/bookId=(\d+)/)[1]}}","chapterId":"{{$.serialID}}"}}',
      },
    });
    final book = Book(
      bookUrl: 'https://example.com/book/1',
      tocUrl: 'https://example.com/toc?bookId=1137339371',
      origin: 'DragonQuestQBqqnv',
      originName: '測試目錄書源',
    );

    const tocJson = '''
{
  "rows": [
    {"serialID": 101, "serialName": "第一章"},
    {"serialID": 102, "serialName": "第二章"}
  ]
}
''';

    final result = await ChapterListParser.parse(
      source: source,
      book: book,
      body: tocJson,
      baseUrl: book.tocUrl,
    );

    expect(result.chapters, hasLength(2));
    expect(result.chapters[0].title, '第一章');
    expect(
      result.chapters[0].url,
      'https://example.com/content,{"method":"POST","body":{"bookId":"1137339371","chapterId":"101"}}',
    );
    expect(
      result.chapters[1].url,
      'https://example.com/content,{"method":"POST","body":{"bookId":"1137339371","chapterId":"102"}}',
    );
  }, skip: quickJsSkip);

  test('ChapterListParser respects maxChapters limit', () async {
    final source = BookSource.fromJson({
      'bookSourceUrl': 'https://example.com',
      'bookSourceName': '限制測試書源',
      'ruleToc': {
        'chapterList': r'$.rows',
        'chapterName': r'$.serialName',
        'chapterUrl': r'$.serialID',
      },
    });
    final book = Book(
      bookUrl: 'https://example.com/book/1',
      tocUrl: 'https://example.com/toc',
      origin: 'https://example.com',
      originName: '限制測試書源',
    );

    const tocJson = '''
{
  "rows": [
    {"serialID": "1", "serialName": "第一章"},
    {"serialID": "2", "serialName": "第二章"},
    {"serialID": "3", "serialName": "第三章"}
  ]
}
''';

    final result = await ChapterListParser.parse(
      source: source,
      book: book,
      body: tocJson,
      baseUrl: book.tocUrl,
      maxChapters: 2,
    );

    expect(result.chapters, hasLength(2));
    expect(result.chapters.map((chapter) => chapter.title), <String>[
      '第一章',
      '第二章',
    ]);
    expect(result.nextUrls, isEmpty);
  });

  test(
    'ChapterListParser exposes chapter context during chapterUrl js evaluation',
    () async {
      final source = BookSource.fromJson({
        'bookSourceUrl': 'https://example.com',
        'bookSourceName': '章節上下文測試書源',
        'ruleToc': {
          'chapterList': 'li',
          'chapterName': 'a@text',
          'chapterUrl': r'''<js>
chapter.putVariable("capturedTitle", chapter.title);
chapter.putVariable("capturedHref", java.getString("a@href"));
java.getString("a@href");
</js>''',
        },
      });
      final book = Book(
        bookUrl: 'https://example.com/book/1',
        tocUrl: 'https://example.com/book/1/index.html',
        origin: 'https://example.com',
        originName: '章節上下文測試書源',
      );

      const tocHtml = '''
<ul class="chapters">
  <li><a href="/chapter/1">第一章</a></li>
  <li><a href="/chapter/2">第二章</a></li>
</ul>
''';

      final result = await ChapterListParser.parse(
        source: source,
        book: book,
        body: tocHtml,
        baseUrl: book.tocUrl,
      );

      expect(result.chapters, hasLength(2));
      expect(result.chapters[0].title, '第一章');
      expect(result.chapters[0].url, 'https://example.com/chapter/1');
      expect(result.chapters[0].getVariable('capturedTitle'), '第一章');
      expect(result.chapters[0].getVariable('capturedHref'), '/chapter/1');
    },
    skip: quickJsSkip,
  );

  test(
    'ChapterListParser accepts Jsoup selection results returned from js rules',
    () async {
      final source = BookSource.fromJson({
        'bookSourceUrl': 'https://example.com',
        'bookSourceName': 'Jsoup 目录回传测试书源',
        'ruleToc': {
          'chapterList': r'''<js>
org.jsoup.Jsoup.parse('<div><a href="/chapter/1">第一章</a><a href="/chapter/2">第二章</a></div>').select('a')
</js>''',
          'chapterName': 'text',
          'chapterUrl': 'href',
        },
      });
      final book = Book(
        bookUrl: 'https://example.com/book/1',
        tocUrl: 'https://example.com/book/1/index.html',
        origin: 'https://example.com',
        originName: 'Jsoup 目录回传测试书源',
      );

      final result = await ChapterListParser.parse(
        source: source,
        book: book,
        body: '<html></html>',
        baseUrl: book.tocUrl,
      );

      expect(result.chapters, hasLength(2));
      expect(result.chapters[0].title, '第一章');
      expect(result.chapters[0].url, 'https://example.com/chapter/1');
      expect(result.chapters[1].title, '第二章');
      expect(result.chapters[1].url, 'https://example.com/chapter/2');
    },
    skip: quickJsSkip,
  );

  test('ChapterListParser supports legado legacy regex toc rules', () async {
    final source = BookSource.fromJson({
      'bookSourceUrl': 'https://example.com',
      'bookSourceName': 'Legacy Regex 目录书源',
      'ruleToc': {
        'chapterList': r':(?s)(\d+)" class="(isvip)?[^"]*name[^>]*>([^<]*)',
        'chapterName': r'$2$3',
        'chapterUrl': r'https://a.heiyan.com/ajax/chapter/content/$1',
      },
    });
    final book = Book(
      bookUrl: 'https://example.com/book/1',
      tocUrl: 'https://example.com/chapter/1',
      origin: 'https://example.com',
      originName: 'Legacy Regex 目录书源',
    );

    const tocHtml = '''
<ul class="float-list fill-block">
  <li><a href="https://www.heiyan.com/book/143131/11804588" class="name">第一章</a></li>
  <li><a href="https://www.heiyan.com/book/143131/11804591" class="isvip name">第二章</a></li>
</ul>
''';

    final result = await ChapterListParser.parse(
      source: source,
      book: book,
      body: tocHtml,
      baseUrl: book.tocUrl,
    );

    expect(result.chapters, hasLength(2));
    expect(result.chapters[0].title, '第一章');
    expect(
      result.chapters[0].url,
      'https://a.heiyan.com/ajax/chapter/content/11804588',
    );
    expect(result.chapters[1].title, 'isvip第二章');
    expect(
      result.chapters[1].url,
      'https://a.heiyan.com/ajax/chapter/content/11804591',
    );
  });
}
