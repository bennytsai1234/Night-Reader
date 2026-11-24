import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/web_book/chapter_list_parser.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/source/book_source.dart';

import '../../../test_helper.dart';

/// 書源校驗只要目錄前幾章（ADR 0057）：同一頁後面有書源標了付費的章時，接
/// 一章在最後，校驗才看得出這個書源有付費章節。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupTestDI();

  BookSource source({bool vipRule = true}) => BookSource.fromJson({
    'bookSourceName': '付費',
    'bookSourceUrl': 'https://novels.test',
    'ruleToc': {
      'chapterList': 'tag.li',
      'chapterName': 'tag.a@text',
      'chapterUrl': 'tag.a@href',
      if (vipRule) 'isVip': 'class.vip@text',
    },
  });

  String html(int paidAt) =>
      '<html><body><ul>${[for (var i = 1; i <= 12; i++) '<li><a href="/c/$i.html">第$i章</a>'
            '${i == paidAt ? '<b class="vip">true</b>' : ''}</li>'].join()}</ul></body></html>';

  Future<List<String>> titles(BookSource s, int paidAt) async {
    final result = await ChapterListParser.parse(
      source: s,
      book: Book(bookUrl: 'https://novels.test/b/1', origin: s.bookSourceUrl),
      body: html(paidAt),
      baseUrl: 'https://novels.test/b/1',
      maxChapters: 8,
    );
    return [
      for (final c in result.chapters) '${c.title}${c.isLocked ? '🔒' : ''}',
    ];
  }

  test('第 9 章以後才付費：前 8 章之後接上那一章', () async {
    expect(await titles(source(), 10), [
      for (var i = 1; i <= 8; i++) '第$i章',
      '第10章🔒',
    ]);
  });

  test('沒有付費章、或書源沒寫付費規則：只有前 8 章', () async {
    expect(await titles(source(), 0), hasLength(8));
    expect(await titles(source(vipRule: false), 10), hasLength(8));
  });

  test('後面的卷名旁寫著 VIP 不算付費章節', () async {
    final s = BookSource.fromJson({
      'bookSourceName': '付費',
      'bookSourceUrl': 'https://novels.test',
      'ruleToc': {
        'chapterList': 'tag.li',
        'chapterName': 'tag.a@text||tag.span@text',
        'chapterUrl': 'tag.a@href',
        'isVolume': 'class.volume@text',
        'isVip': 'class.vip@text',
      },
    });
    final body =
        '<ul>${[for (var i = 1; i <= 8; i++) '<li><a href="/c/$i.html">第$i章</a></li>'].join()}'
        '<li><span>第二卷</span><i class="volume">卷</i><b class="vip">VIP</b></li>'
        '<li><a href="/c/9.html">第9章</a></li></ul>';
    final result = await ChapterListParser.parse(
      source: s,
      book: Book(bookUrl: 'https://novels.test/b/1', origin: s.bookSourceUrl),
      body: body,
      baseUrl: 'https://novels.test/b/1',
      maxChapters: 8,
    );
    expect(result.chapters.where((c) => c.isLocked), isEmpty);
  });
}
