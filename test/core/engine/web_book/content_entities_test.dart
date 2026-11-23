import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/web_book/content_parser.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/core/models/source/book_source.dart';

import '../../../test_helper.dart';

/// 正文先清標籤再解實體（同 Legado `BookContent`）：原文寫著的標籤字樣
/// （網頁原始碼是 `&amp;lt;span&amp;gt;`）留在正文裡，不被當成標籤刪掉。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupTestDI();

  final book = Book(bookUrl: 'https://e.test/b', origin: 'https://e.test');
  final chapter = BookChapter(url: 'https://e.test/c/1', title: '第一章');

  Future<String> contentOf(String rule) async {
    final source = BookSource.fromJson({
      'bookSourceName': '實體',
      'bookSourceUrl': 'https://e.test',
      'ruleContent': {'content': rule},
    });
    final result = await ContentParser.parse(
      source: source,
      book: book,
      chapter: chapter,
      body: '<div id="c"><p>原文寫的是 &amp;lt;span&amp;gt;。</p></div>',
      baseUrl: chapter.url,
    );
    return result.content;
  }

  test('取文字（@text）的正文留著原文的標籤字樣', () async {
    expect(await contentOf('id.c@text'), contains('原文寫的是 <span>。'));
  });

  test('取 HTML（@html）的正文清掉真的標籤，原文的字樣留著', () async {
    final content = await contentOf('id.c@html');
    expect(content, contains('原文寫的是 &lt;span&gt;。'));
    expect(content, isNot(contains('<p>')));
  });
}
