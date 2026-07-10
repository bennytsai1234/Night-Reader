import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_chapter_repository.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_engine.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_progress_controller.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_runtime.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_state.dart';

class _RecordingBookDao extends Fake implements BookDao {
  final List<ReaderV2Location> savedLocations = <ReaderV2Location>[];

  @override
  Future<void> updateProgress(
    String bookUrl,
    int chapterIndex,
    String chapterTitle,
    int pos, {
    double visualOffsetPx = 0.0,
    String? readerAnchorJson,
  }) async {
    savedLocations.add(
      ReaderV2Location(
        chapterIndex: chapterIndex,
        charOffset: pos,
        visualOffsetPx: visualOffsetPx,
      ),
    );
  }
}

class _FakeChapterDao extends Fake implements ChapterDao {}

class _FakeSourceDao extends Fake implements BookSourceDao {}

ReaderV2LayoutSpec _layoutSpec() {
  return ReaderV2LayoutSpec.fromViewport(
    viewportSize: const Size(360, 640),
    style: const ReaderV2LayoutStyle(
      fontSize: 18,
      lineHeight: 1.6,
      letterSpacing: 0,
      paragraphSpacing: 0.8,
      paddingTop: 24,
      paddingBottom: 24,
      paddingLeft: 20,
      paddingRight: 20,
      textIndent: 2,
    ),
  );
}

BookChapter _chapter(int index) {
  return BookChapter(
    url: 'chapter_$index',
    title: '第 $index 章',
    bookUrl: 'https://book.test',
    index: index,
    content: '章節 $index 的短內容。',
  );
}

({ReaderV2Runtime runtime, _RecordingBookDao bookDao}) _makeRuntime() {
  final book = Book(
    bookUrl: 'https://book.test',
    name: '測試書',
    author: '作者',
    origin: 'local',
    originName: '本地',
  );
  final bookDao = _RecordingBookDao();
  final repository = ReaderV2ChapterRepository(
    book: book,
    initialChapters: <BookChapter>[_chapter(0), _chapter(1), _chapter(2)],
    bookDao: bookDao,
    chapterDao: _FakeChapterDao(),
    sourceDao: _FakeSourceDao(),
  );
  final runtime = ReaderV2Runtime(
    book: book,
    repository: repository,
    layoutEngine: ReaderV2LayoutEngine(),
    progressController: ReaderV2ProgressController(
      book: book,
      repository: repository,
      bookDao: bookDao,
    ),
    initialLayoutSpec: _layoutSpec(),
    initialLocation: const ReaderV2Location(chapterIndex: 0, charOffset: 0),
  );
  return (runtime: runtime, bookDao: bookDao);
}

void main() {
  group('ReaderV2 navigation and viewport boundaries', () {
    test('跳章索引會夾在首末章，且首尾外翻安全地回傳 false', () async {
      final harness = _makeRuntime();
      final runtime = harness.runtime;
      addTearDown(runtime.dispose);

      await runtime.openBook();
      expect(runtime.state.phase, ReaderV2Phase.ready);

      await runtime.navigation.jumpToChapter(-100);
      expect(runtime.state.visibleLocation.chapterIndex, 0);
      expect(runtime.state.visibleLocation.charOffset, 0);
      expect(
        runtime.navigation.moveToPrevPage(saveSettledProgress: false),
        isFalse,
      );

      await runtime.navigation.jumpToChapter(100);
      expect(runtime.state.visibleLocation.chapterIndex, 2);
      expect(runtime.state.visibleLocation.charOffset, 0);
      expect(
        runtime.navigation.moveToNextPage(saveSettledProgress: false),
        isFalse,
      );
    });

    test(
      '沒有 viewport capture 時 saveProgress 安全失敗，flushProgress 使用 session 位置',
      () async {
        final harness = _makeRuntime();
        final runtime = harness.runtime;
        final bookDao = harness.bookDao;
        addTearDown(runtime.dispose);

        await runtime.openBook();
        final visibleBefore = runtime.state.visibleLocation;

        expect(await runtime.viewportBridge.saveProgress(), isNull);
        expect(runtime.state.visibleLocation, visibleBefore);
        expect(bookDao.savedLocations, isEmpty);

        const fallbackLocation = ReaderV2Location(
          chapterIndex: 1,
          charOffset: 5,
        );
        runtime.updateVisibleLocation(fallbackLocation);
        final flushed = await runtime.viewportBridge.flushProgress();
        expect(flushed, fallbackLocation);
        expect(bookDao.savedLocations, <ReaderV2Location>[fallbackLocation]);
      },
    );

    test('沒有 viewport restore 時 restoreFromLocation 不啟動 restore 操作', () async {
      final harness = _makeRuntime();
      final runtime = harness.runtime;
      addTearDown(runtime.dispose);

      final restored = await runtime.navigation.restoreFromLocation(
        const ReaderV2Location(chapterIndex: 99, charOffset: 99),
      );

      expect(restored, isFalse);
      expect(runtime.state.phase, ReaderV2Phase.cold);
      expect(runtime.restoreInProgress, isFalse);
      expect(
        runtime.state.visibleLocation,
        const ReaderV2Location(chapterIndex: 0, charOffset: 0),
      );
    });
  });
}
