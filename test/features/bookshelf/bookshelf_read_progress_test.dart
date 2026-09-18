import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/features/bookshelf/bookshelf_read_progress.dart';

void main() {
  Book book({
    int totalChapterNum = 0,
    int chapterIndex = 0,
    int charOffset = 0,
    int durChapterTime = 0,
  }) {
    return Book(
      totalChapterNum: totalChapterNum,
      chapterIndex: chapterIndex,
      charOffset: charOffset,
      durChapterTime: durChapterTime,
    );
  }

  test('未知章節數與未開始閱讀都顯示 0%', () {
    expect(bookshelfReadProgress(book()), 0.0);
    expect(bookshelfReadProgress(book(totalChapterNum: 10)), 0.0);
  });

  test('單章書開始閱讀後可顯示 100%', () {
    expect(
      bookshelfReadProgress(
        book(totalChapterNum: 1, charOffset: 1, durChapterTime: 1),
      ),
      1.0,
    );
  });

  test('以已讀到的章節計算進度，最後一章可顯示 100%', () {
    expect(
      bookshelfReadProgress(
        book(totalChapterNum: 10, chapterIndex: 4, durChapterTime: 1),
      ),
      0.5,
    );
    expect(
      bookshelfReadProgress(
        book(totalChapterNum: 10, chapterIndex: 9, durChapterTime: 1),
      ),
      1.0,
    );
  });

  test('異常章節索引會限制在有效範圍', () {
    expect(
      bookshelfReadProgress(
        book(totalChapterNum: 10, chapterIndex: 99, durChapterTime: 1),
      ),
      1.0,
    );
  });
}
