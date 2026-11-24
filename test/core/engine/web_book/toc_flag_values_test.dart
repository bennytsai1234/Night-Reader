import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/web_book/chapter_list_parser.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/source/book_source.dart';

import '../../../test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupTestDI();

  const tocUrl = 'https://novels.test/book/1/';

  // 「是不是卷、是不是付費」的規則回的是元素的文字或屬性，不一定是 true。
  const html = '''
<html><body><ul>
  <li class="volume"><span>第一卷</span></li>
  <li><a href="/c/1.html">第一章</a></li>
  <li><a href="/c/2.html">第二章</a><img class="lock" src="/img/lock.png"></li>
  <li><a href="/c/3.html">第三章</a><i class="tag">VIP</i></li>
  <li><a href="/c/4.html">第四章</a><i class="tag">no</i></li>
  <li><a href="/c/5.html">第五章</a><i class="tag">FALSE</i></li>
  <li><a href="/c/6.html">第六章</a><i class="tag">0</i></li>
  <li><a href="/c/7.html">第七章</a><i class="tag">null</i></li>
</ul></body></html>
''';

  BookSource source() => BookSource.fromJson({
    'bookSourceName': '旗標',
    'bookSourceUrl': 'https://novels.test',
    'ruleToc': {
      'chapterList': 'tag.li',
      'chapterName': 'tag.span@text||tag.a@text',
      'chapterUrl': 'tag.a@href',
      'isVolume': '@css:li.volume@class',
      'isVip': 'class.lock@src',
      'isPay': 'class.tag@text',
    },
  });

  test('卷名、付費照 Legado 的 isTrue：不是空的、不是 false／no／not／0 就算是', () async {
    final chapters = (await ChapterListParser.parse(
      source: source(),
      book: Book(
        bookUrl: tocUrl,
        tocUrl: tocUrl,
        origin: 'https://novels.test',
      ),
      body: html,
      baseUrl: tocUrl,
    )).chapters;

    expect(chapters.map((c) => c.title), [
      '第一卷',
      '第一章',
      '第二章',
      '第三章',
      '第四章',
      '第五章',
      '第六章',
      '第七章',
    ]);
    expect(chapters[0].isVolume, isTrue, reason: 'class 屬性的值');
    expect(chapters.skip(1).any((c) => c.isVolume), isFalse);
    expect(chapters[2].isVip, isTrue, reason: '鎖頭圖片的網址');
    expect(chapters[3].isPay, isTrue, reason: '「VIP」字樣');
    expect(chapters[4].isPay, isFalse);
    expect(chapters[5].isPay, isFalse, reason: '不分大小寫');
    expect(chapters[6].isPay, isFalse);
    expect(chapters[7].isPay, isFalse, reason: 'Legado 把 "null" 當空的');
    expect(chapters[1].isPay || chapters[1].isVip, isFalse);
  });
}
