import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/web_book/web_book_service.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/source/book_source.dart';

import '../../../test_helper.dart';

/// 目錄的 `formatJs`，同 Legado `BookChapterList.analyzeChapterList`：目錄排成
/// 最後的順序、編好號之後逐章跑，`index` 從 1 起、`title` 是原章名、`gInt`
/// 是整份目錄共用、從 0 起的計數。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupTestDI();

  const tocUrl = 'https://novels.test/book/1/';
  const html = '''
<html><body><ul>
  <li><a href="/c/1.html">開端</a></li>
  <li><a href="/c/2.html">相遇</a></li>
  <li><a href="/c/3.html">離別</a></li>
</ul></body></html>
''';

  BookSource source(String formatJs, {String chapterList = 'tag.li'}) =>
      BookSource.fromJson({
        'bookSourceName': '目錄',
        'bookSourceUrl': 'https://novels.test',
        'ruleToc': {
          'chapterList': chapterList,
          'chapterName': 'tag.a@text',
          'chapterUrl': 'tag.a@href',
          'formatJs': formatJs,
        },
      });

  Book book({bool reverseToc = false}) =>
      Book(
          bookUrl: tocUrl,
          tocUrl: tocUrl,
          origin: 'https://novels.test',
          name: '書',
        )
        ..tocHtml = html
        ..readConfig = (ReadConfig()..reverseToc = reverseToc);

  Future<List<String>> titles(BookSource source, Book book) async => [
    for (final c in await WebBook.getChapterListAwait(source, book)) c.title,
  ];

  test('index numbers the chapters from 1 in the shown order', () async {
    expect(await titles(source("'第'+index+'章 '+title"), book()), [
      '第1章 開端',
      '第2章 相遇',
      '第3章 離別',
    ]);
  }, skip: quickJsUnavailableReason());

  test('gInt is one counter for the whole table of contents', () async {
    expect(await titles(source("(++gInt)+'.'+title"), book()), [
      '1.開端',
      '2.相遇',
      '3.離別',
    ]);
  }, skip: quickJsUnavailableReason());

  test('numbers follow the order shown when the list is reversed', () async {
    // 書源寫了 `-`：網站列的是倒序，排好後是 離別、相遇、開端。
    expect(
      await titles(source("index+'.'+title", chapterList: '-tag.li'), book()),
      ['1.離別', '2.相遇', '3.開端'],
    );
    // 讀者反轉目錄。
    expect(await titles(source("index+'.'+title"), book(reverseToc: true)), [
      '1.離別',
      '2.相遇',
      '3.開端',
    ]);
  }, skip: quickJsUnavailableReason());
}
