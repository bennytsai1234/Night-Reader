import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/book/chapter_alignment.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';

void main() {
  List<BookChapter> toc(List<String> titles) => [
    for (final (i, title) in titles.indexed)
      BookChapter(url: '/c/$i', title: title, index: i),
  ];

  test('when several chapters share the title, the one nearest the old '
      'position wins, not the first', () {
    final chapters = toc(['第一章', '番外', '第二章', '第三章', '番外', '第四章']);
    int align(int oldIndex, {int oldTotalCount = 0}) => alignChapterIndex(
      oldIndex: oldIndex,
      oldTitle: '番外',
      oldTotalCount: oldTotalCount,
      newChapters: chapters,
    );
    expect(align(4), 4);
    expect(align(1), 1);
    // 新目錄多一章：照比例估的位置（4 × 6 / 5 ≈ 5）附近那個。
    expect(align(4, oldTotalCount: 5), 4);
  });

  test('a single matching title still wins wherever it is', () {
    final chapters = toc(['楔子', '第一章', '第二章']);
    expect(
      alignChapterIndex(
        oldIndex: 0,
        oldTitle: '第二章',
        oldTotalCount: 0,
        newChapters: chapters,
      ),
      2,
    );
  });

  // 照 Legado `BookHelp.getDurChapter`：章名寫法不同時，去掉章號比章名本身，
  // 再比章號（認中文數字與「100、」這種寫法）。
  group('章名寫法不同（同 Legado）', () {
    // 新目錄前面多了 5 章（作品相關、請假條），照比例估的位置（約 101）
    // 和真正的位置（104）不同，要靠章名或章號對上。
    List<String> numbered(String Function(int n) title) => [
      for (var i = 1; i <= 5; i++) '作品相關$i',
      for (var n = 1; n <= 200; n++) title(n),
    ];
    int align(String oldTitle, List<String> titles) => alignChapterIndex(
      oldIndex: 99,
      oldTitle: oldTitle,
      oldTotalCount: 200,
      newChapters: toc(titles),
    );

    test('章號寫成中文數字', () {
      const names = ['風起', '雲湧'];
      final titles = numbered(
        (n) => '第${_chinese(n)}章 ${names[n % 2]}${n == 100 ? '' : n}',
      );
      expect(align('第100章 風起', titles), 104);
    });

    test('章號寫成「100、」', () {
      final titles = numbered((n) => '第$n章 章名$n');
      expect(align('100、章名100', titles), 104);
    });

    test('章號對不上、章名本身一樣（網站多算一章）', () {
      final titles = numbered((n) => '第$n章 章名${n - 1}');
      // 舊的是「第100章 章名100」，新目錄的「第101章 章名100」才是同一章。
      expect(align('第100章 章名100', titles), 105);
    });

    test('章名外面多了括號裡的字', () {
      final titles = numbered((n) => '第$n章 章名$n');
      expect(align('第100章 章名100（求月票）', titles), 104);
    });
  });
}

String _chinese(int n) {
  const digits = ['零', '一', '二', '三', '四', '五', '六', '七', '八', '九'];
  if (n < 10) return digits[n];
  if (n < 20) return '十${n % 10 == 0 ? '' : digits[n % 10]}';
  if (n < 100) {
    return '${digits[n ~/ 10]}十${n % 10 == 0 ? '' : digits[n % 10]}';
  }
  final rest = n % 100;
  return '${digits[n ~/ 100]}百'
      '${rest == 0
          ? ''
          : rest < 10
          ? '零${digits[rest]}'
          : rest < 20
          ? '一${_chinese(rest)}'
          : _chinese(rest)}';
}
