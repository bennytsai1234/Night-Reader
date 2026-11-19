import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/core/source_check/content_samples.dart';

void main() {
  BookChapter chapter(int index, {String? title, bool vip = false}) =>
      BookChapter(
        url: 'chapter_$index',
        title: title ?? '第 $index 章',
        bookUrl: 'book',
        index: index,
        isVip: vip,
      );
  List<BookChapter> book(int count) => [
    for (var i = 0; i < count; i++) chapter(i),
  ];

  group('中段、後段抽哪幾章', () {
    test('前五章以內的短書不抽', () {
      expect(laterSampleIndexes(book(5)), isEmpty);
    });

    test('抽一半、四分之三、九成的位置', () {
      expect(laterSampleIndexes(book(100)), [50, 75, 90]);
    });

    test('章名寫了 VIP 的優先，頂替後兩個位置', () {
      final chapters = book(100)
        ..[60] = chapter(60, title: '第 60 章 VIP')
        ..[80] = chapter(80, title: '第 80 章 VIP');
      expect(laterSampleIndexes(chapters), [50, 60, 80]);
    });
  });

  test('開頭抽查時章名像付費章的排到最後', () {
    final chapters = book(5)..[0] = chapter(0, title: '第 0 章（付費）');
    expect(buildContentProbeIndexes(chapters, 5), [1, 2, 3, 4, 0]);
  });

  test('書源標了付費、或章名有付費字樣，都算像付費章', () {
    expect(looksLikeLockedChapter(chapter(1, vip: true)), isTrue);
    expect(looksLikeLockedChapter(chapter(1, title: '第一章 訂閱')), isTrue);
    expect(looksLikeLockedChapter(chapter(1)), isFalse);
  });

  group('兩章一半以上是同一段文字', () {
    test('一樣的廣告算', () {
      const ad = '本站新域名請收藏。點擊下載閱讀器。更多好書盡在本站。';
      expect(sharedSentences(ad, ad), isNotNull);
    });

    test('不同的正文不算，只共用一句作者的話也不算', () {
      const note = '求月票。';
      final a = '$note${List.filled(20, '主角走進城裡。').join()}';
      final b = '$note${List.filled(20, '配角留在山上。').join()}';
      expect(sharedSentences(a, b), isNull);
    });
  });

  test('目錄或第一章的網址是下載檔，就是下載站', () {
    Book at(String url, {String origin = 'source'}) =>
        Book(bookUrl: url, origin: origin);
    expect(looksLikeDownloadOnly(at('https://x/book.zip'), const []), isTrue);
    expect(
      looksLikeDownloadOnly(at('https://x/book/1'), [chapter(0)]),
      isFalse,
    );
    expect(
      looksLikeDownloadOnly(at('https://x/a.txt', origin: ''), const []),
      isFalse,
      reason: '沒有書源的本地書不算',
    );
  });
}
