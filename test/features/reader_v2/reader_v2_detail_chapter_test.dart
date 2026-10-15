import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_page.dart';

void main() {
  const bookUrl = 'https://s.example/book/1';
  BookChapter chapter(String id, int index) => BookChapter(
    url: '$bookUrl/$id',
    title: id,
    bookUrl: bookUrl,
    index: index,
  );

  // 閱讀器開書時的目錄；之後書架檢查在最前面插了一章「序」、最後多了「c」。
  final reader = [chapter('a', 0), chapter('b', 1)];
  final latest = [
    chapter('序', 0),
    chapter('a', 1),
    chapter('b', 2),
    chapter('c', 3),
  ];

  test('a chapter the reader has is opened by its own index', () async {
    var loaded = false;
    final target = await resolveDetailChapter(
      url: '$bookUrl/b',
      readerChapters: reader,
      loadLatest: () async {
        loaded = true;
        return latest;
      },
    );
    expect(target, (index: 1, latest: null));
    expect(loaded, isFalse);
  });

  test('a chapter only in the newer table of contents reopens on it', () async {
    final target = await resolveDetailChapter(
      url: '$bookUrl/c',
      readerChapters: reader,
      loadLatest: () async => latest,
    );
    expect(target?.index, 3);
    expect(target?.latest, same(latest));
  });

  test('a chapter nowhere to be found does nothing', () async {
    final target = await resolveDetailChapter(
      url: '$bookUrl/gone',
      readerChapters: reader,
      loadLatest: () async => latest,
    );
    expect(target, isNull);
  });
}
