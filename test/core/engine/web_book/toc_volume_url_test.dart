import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/web_book/chapter_list_parser.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';

import '../../../test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupTestDI();

  const tocUrl = 'https://novels.test/book/1/';
  // 兩個卷標題（沒有網址、有 class="v" 的標記）夾著三章，其中一章沒有連結。
  const html = '''
<html><body><ul>
  <li><span>第一卷</span><b class="v">true</b></li>
  <li><a href="/c/1.html">第一章</a></li>
  <li><a>第二章 沒有連結</a></li>
  <li><span>第二卷</span><b class="v">true</b></li>
  <li><a href="c/3.html">第三章</a></li>
</ul></body></html>
''';

  BookSource source() => BookSource.fromJson({
    'bookSourceName': '卷',
    'bookSourceUrl': 'https://novels.test',
    'ruleToc': {
      'chapterList': 'tag.li',
      'chapterName': 'tag.span@text||tag.a@text',
      'chapterUrl': 'tag.a@href',
      'isVolume': 'class.v@text',
    },
  });

  Book book() =>
      Book(bookUrl: tocUrl, tocUrl: tocUrl, origin: 'https://novels.test');

  test('卷沒有章節網址時用「標題＋序號」，不是目錄網址（同 Legado）', () async {
    final result = await ChapterListParser.parse(
      source: source(),
      book: book(),
      body: html,
      baseUrl: tocUrl,
    );
    final chapters = result.chapters;

    expect(chapters.map((c) => c.title), [
      '第一卷',
      '第一章',
      '第二章 沒有連結',
      '第二卷',
      '第三章',
    ]);
    expect(chapters[0].isVolume, isTrue);
    expect(chapters[0].url, '第一卷0');
    expect(chapters[3].isVolume, isTrue);
    expect(chapters[3].url, '第二卷3');
    // 兩個卷的網址不同，依網址去重不會把它們收成一個。
    expect(chapters.map((c) => c.url).toSet(), hasLength(chapters.length));
  });

  test('一般章節：有網址補成絕對網址，沒網址退回目錄網址', () async {
    final result = await ChapterListParser.parse(
      source: source(),
      book: book(),
      body: html,
      baseUrl: tocUrl,
    );
    final chapters = result.chapters;

    expect(chapters[1].url, 'https://novels.test/c/1.html');
    expect(chapters[2].isVolume, isFalse);
    expect(chapters[2].url, tocUrl);
    expect(chapters[4].url, 'https://novels.test/book/1/c/3.html');
  });
}
