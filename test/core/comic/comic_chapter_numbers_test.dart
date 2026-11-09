import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/comic/comic_chapter_numbers.dart';

void main() {
  test('認得常見的章名寫法', () {
    expect(ComicChapterNumbers.of('第12話 出發'), 12);
    expect(ComicChapterNumbers.of('第１２话'), 12);
    expect(ComicChapterNumbers.of('第十二話'), 12);
    expect(ComicChapterNumbers.of('第一百零五回'), 105);
    expect(ComicChapterNumbers.of('第二十章'), 20);
    expect(ComicChapterNumbers.of('Vol.2 Ch.33.5 Title'), 33.5);
    expect(ComicChapterNumbers.of('12 標題'), 12);
    expect(ComicChapterNumbers.of('第3卷'), isNull);
    expect(ComicChapterNumbers.of('番外'), isNull);
  });

  test('中間缺幾話：只看整數部分，認不出來不提醒', () {
    expect(ComicChapterNumbers.gapBetween('第12話', '第15話'), 2);
    expect(ComicChapterNumbers.gapBetween('第12話', '第13話'), 0);
    expect(ComicChapterNumbers.gapBetween('第12.5話', '第13話'), 0);
    expect(ComicChapterNumbers.gapBetween('番外', '第13話'), 0);
    expect(ComicChapterNumbers.gapBetween('第13話', '第12話'), 0);
  });
}
