import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/web_book/chapter_list_parser.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';

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
}
