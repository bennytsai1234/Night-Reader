import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/web_book/chapter_list_parser.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';

import '../../test_helper.dart';

/// 目錄解析要隨章數線性成長。章節連結是同一層的上千個兄弟節點，任何
/// 「逐章掃一次全部兄弟」的寫法都會變成平方級，長篇小說的目錄就要好幾秒，
/// 而且是在主執行緒上（docs/research/source-engine-off-main-isolate.md）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupTestDI();

  final source = BookSource.fromJson({
    'bookSourceName': '目錄效能',
    'bookSourceUrl': 'https://toc.test',
    'ruleToc': {
      'chapterList': 'class.list@a',
      'chapterName': 'a@text',
      'chapterUrl': 'a@href',
    },
  });
  final book = Book(
    bookUrl: 'https://toc.test/book/',
    origin: 'https://toc.test',
    name: '目錄效能',
    tocUrl: 'https://toc.test/book/',
  );

  String tocHtml(int chapters) =>
      '<html><body><div class="list">'
      '${List.generate(chapters, (i) => '<a href="/book/$i.html">第${i + 1}章</a>').join()}'
      '</div></body></html>';

  /// 取三次中最快的一次，減少機器忙碌造成的雜訊。
  Future<int> fastestMicros(int chapters) async {
    final html = tocHtml(chapters);
    var best = 1 << 62;
    for (var run = 0; run < 3; run++) {
      final watch = Stopwatch()..start();
      final result = await ChapterListParser.parse(
        source: source,
        book: book,
        body: html,
        baseUrl: book.tocUrl,
      );
      watch.stop();
      expect(result.chapters, hasLength(chapters));
      if (watch.elapsedMicroseconds < best) best = watch.elapsedMicroseconds;
    }
    return best;
  }

  test('a TOC four times longer takes far less than sixteen times as '
      'long', () async {
    await fastestMicros(500);
    final small = await fastestMicros(1000);
    final large = await fastestMicros(4000);

    // 線性約 4 倍，平方級約 16 倍；留足雜訊空間，只擋平方級。
    expect(
      large / small,
      lessThan(9),
      reason: '1000 章 $small µs，4000 章 $large µs',
    );
  });

  test('a simple selector still matches the element itself', () async {
    final result = await ChapterListParser.parse(
      source: source,
      book: book,
      body: tocHtml(3),
      baseUrl: book.tocUrl,
    );

    expect(result.chapters.map((c) => c.title), ['第1章', '第2章', '第3章']);
    expect(result.chapters.first.url, 'https://toc.test/book/0.html');
  });
}
