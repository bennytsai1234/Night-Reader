import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/book/chapter_alignment.dart';
import 'package:night_reader/core/models/chapter.dart';

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
}
