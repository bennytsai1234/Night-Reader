import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/comic_reader/comic_strip_model.dart';

import 'comic_test_pages.dart';

Future<void> _idle() => Future<void>.delayed(const Duration(milliseconds: 10));

void main() {
  test('a neighbouring chapter that failed is not loaded again on its own; '
      'retry loads it', () async {
    final source = FakeComicSource()..failingChapters.add(1);
    final model = ComicStripModel(
      source: source,
      chapterCount: 3,
      chapterIndex: 0,
    )..start();
    await _idle();

    model.loadNext();
    await _idle();
    expect(model.stateOf(1), isA<ComicChapterFailed>());
    // 捲動每一幀都會問：失敗過的不再自己去抓。
    for (var i = 0; i < 5; i++) {
      model.loadNext();
    }
    await _idle();
    expect(source.requestedChapters.where((c) => c == 1), hasLength(1));

    source.failingChapters.clear();
    model.retry(1);
    await _idle();
    expect(model.stateOf(1), isA<ComicChapterReady>());
    model.dispose();
  });

  test('retryFailed loads every chapter that failed and leaves the loaded '
      'ones alone', () async {
    final source = FakeComicSource()..failingChapters.addAll([0, 1]);
    final model = ComicStripModel(
      source: source,
      chapterCount: 3,
      chapterIndex: 0,
    )..start();
    await _idle();
    expect(model.stateOf(0), isA<ComicChapterFailed>());

    source.failingChapters.clear();
    model.retryFailed();
    await _idle();
    expect(model.stateOf(0), isA<ComicChapterReady>());
    // 錨點那一話放上去後，先拿前後各兩話的圖片清單。
    expect(source.requestedChapters, [0, 0, 1, 2]);

    // 沒有失敗的話時不再抓。
    model.retryFailed();
    await _idle();
    expect(source.requestedChapters, [0, 0, 1, 2]);
    model.dispose();
  });

  test('a chapter with no pages (for example a broken file) is a failure '
      'with a retry, not an empty chapter', () async {
    final model = ComicStripModel(
      source: FakeComicSource(pagesPerChapter: 0),
      chapterCount: 1,
      chapterIndex: 0,
    )..start();
    await _idle();

    expect(model.stateOf(0), isA<ComicChapterFailed>());
    model.dispose();
  });

  test('volume titles in the contents are skipped: opening on one starts at '
      'the next chapter, and the strip goes straight past them', () async {
    // 0 第一卷、1 第1話、2 第二卷、3 第2話
    const volumes = {0, 2};
    final source = FakeComicSource(pagesPerChapter: 1);
    final model = ComicStripModel(
      source: source,
      chapterCount: 4,
      chapterIndex: 0,
      isReadable: (i) => !volumes.contains(i),
    )..start();
    await _idle();

    expect(model.anchorChapter, 1);
    model.loadNext();
    await _idle();
    expect(source.requestedChapters, [1, 3]);
    final transitions = model.after.whereType<ComicTransitionItem>().toList();
    expect(transitions.first.from, 1);
    expect(transitions.first.to, 3);
    expect(transitions.last.to, isNull);
    model.dispose();
  });
}
