import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/use_cases/coordinators/reader_v2_chapter_navigation_resolver.dart';

void main() {
  // 第 2、3 章付費（ADR 0057）。
  bool paid(int index) => index == 2 || index == 3;

  int? resolve(int current, int delta) =>
      ReaderV2ChapterNavigationResolver.resolveRelativeTarget(
        currentChapterIndex: current,
        chapterCount: 6,
        delta: delta,
        skip: paid,
      );

  test('next and previous chapter skip paid chapters', () {
    expect(resolve(1, 1), 4);
    expect(resolve(4, -1), 1);
    expect(resolve(0, 2), 4);
  });

  test('no target past the book edge or when only paid chapters remain', () {
    expect(resolve(5, 1), isNull);
    expect(resolve(0, -1), isNull);
    expect(
      ReaderV2ChapterNavigationResolver.resolveRelativeTarget(
        currentChapterIndex: 1,
        chapterCount: 4,
        delta: 1,
        skip: paid,
      ),
      isNull,
    );
  });

  test('without a skip rule every chapter counts', () {
    expect(
      ReaderV2ChapterNavigationResolver.resolveRelativeTarget(
        currentChapterIndex: 1,
        chapterCount: 6,
        delta: 1,
      ),
      2,
    );
  });
}
