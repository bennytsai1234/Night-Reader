import 'package:flutter/widgets.dart';
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
  final List<({int chapterIndex, int pos})> progressWrites =
      <({int chapterIndex, int pos})>[];

  @override
  Future<void> updateProgress(
    String bookUrl,
    int chapterIndex,
    String chapterTitle,
    int pos, {
    double visualOffsetPx = 0.0,
    String? readerAnchorJson,
  }) async {
    progressWrites.add((chapterIndex: chapterIndex, pos: pos));
  }
}

class _FakeChapterDao extends Fake implements ChapterDao {}

class _FakeSourceDao extends Fake implements BookSourceDao {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ReaderV2LayoutSpec specWithFontSize(double fontSize) {
    return ReaderV2LayoutSpec.fromViewport(
      viewportSize: const Size(220, 180),
      style: ReaderV2LayoutStyle(
        fontSize: fontSize,
        lineHeight: 1.5,
        letterSpacing: 0,
        paragraphSpacing: 0.8,
        paddingTop: 12,
        paddingBottom: 12,
        paddingLeft: 12,
        paddingRight: 12,
        textIndent: 2,
      ),
    );
  }

  BookChapter chapter(int index, {int paragraphCount = 8}) {
    final body = List<String>.generate(
      paragraphCount,
      (p) => '第 $index 章第 $p 段：這是一段用於壓力測試的中文內容，帶有標點符號與足夠的長度以跨越多行。',
    ).join('\n\n');
    return BookChapter(
      url: 'chapter_$index',
      title: '第 $index 章',
      bookUrl: 'http://book.test',
      index: index,
      content: body,
    );
  }

  ({ReaderV2Runtime runtime, _RecordingBookDao bookDao}) makeRuntime(
    List<BookChapter> chapters,
  ) {
    final book = Book(
      bookUrl: 'http://book.test',
      name: '測試書',
      author: '作者',
      origin: 'local',
      originName: '本地',
    );
    final bookDao = _RecordingBookDao();
    final repository = ReaderV2ChapterRepository(
      book: book,
      initialChapters: chapters,
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
        debounce: const Duration(milliseconds: 5),
      ),
      initialLayoutSpec: specWithFontSize(18),
      initialLocation: const ReaderV2Location(chapterIndex: 0, charOffset: 0),
    );
    return (runtime: runtime, bookDao: bookDao);
  }

  group('ReaderV2Runtime 壓力測試', () {
    test('openBook / applyPresentation / reload / jump 交錯後狀態收斂為 ready', () async {
      final harness = makeRuntime([for (var i = 0; i < 10; i++) chapter(i)]);
      final runtime = harness.runtime;
      addTearDown(runtime.dispose);

      await runtime.openBook();
      expect(runtime.state.phase, ReaderV2Phase.ready);
      expect(runtime.state.pageWindow, isNotNull);

      final operations = <Future<void>>[
        runtime.applyPresentation(spec: specWithFontSize(22)),
        runtime.reloadContentPreservingLocation(),
        runtime.jumpToChapter(5),
        runtime.applyPresentation(spec: specWithFontSize(18)),
        runtime.jumpToChapter(2),
        runtime.reloadContentPreservingLocation(),
        runtime.jumpToChapter(8),
      ];
      await Future.wait(operations).timeout(
        const Duration(seconds: 60),
        onTimeout: () => fail('交錯的 session 操作沒有收斂'),
      );
      // 等背景的收尾（preload、debounce 進度）消化一輪。
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final state = runtime.state;
      expect(state.phase, ReaderV2Phase.ready, reason: '交錯操作後必須回到 ready');
      expect(state.errorMessage, isNull);
      expect(state.pageWindow, isNotNull);
      expect(state.visibleLocation.chapterIndex, inInclusiveRange(0, 9));
      expect(
        state.pageWindow!.current.chapterIndex,
        state.visibleLocation.chapterIndex,
        reason: '視窗中心頁必須與可見位置一致',
      );
      expect(
        state.layoutSpec.layoutSignature,
        runtime.resolver.layoutSpec.layoutSignature,
        reason: 'session 與 resolver 的排版 spec 必須一致',
      );
      expect(runtime.pendingChapterJumpTarget, isNull);
    });

    test('兩個 jumpToChapter 交錯時，先結束者不得清掉後到者的 pending target', () async {
      final harness = makeRuntime([
        for (var i = 0; i < 10; i++)
          // 讓後到的目標章節（7）遠大於先到的（3），先到者必定先結束。
          chapter(i, paragraphCount: i == 7 ? 220 : 2),
      ]);
      final runtime = harness.runtime;
      addTearDown(runtime.dispose);
      await runtime.openBook();

      final first = runtime.jumpToChapter(3);
      final second = runtime.jumpToChapter(7);
      await first;
      expect(
        runtime.pendingChapterJumpTarget,
        isNotNull,
        reason: '先結束的 jump 清掉了後到者的 pending target（B8 回歸）',
      );
      await second;
      expect(runtime.pendingChapterJumpTarget, isNull);
      expect(runtime.state.phase, ReaderV2Phase.ready);
      expect(runtime.state.visibleLocation.chapterIndex, 7);
    });

    test('runtime 級翻頁（fallback 路徑）必須保存進度', () async {
      final harness = makeRuntime([
        for (var i = 0; i < 3; i++) chapter(i, paragraphCount: 30),
      ]);
      final runtime = harness.runtime;
      final bookDao = harness.bookDao;
      addTearDown(runtime.dispose);

      await runtime.openBook();
      bookDao.progressWrites.clear();

      expect(runtime.moveToNextPage(), isTrue);
      final expected = runtime.state.visibleLocation;
      expect(
        runtime.state.committedLocation,
        isNot(equals(const ReaderV2Location(chapterIndex: 0, charOffset: 0))),
        reason: '翻頁後 committedLocation 必須跟上（B7 回歸）',
      );
      // 進度走 debounce 寫入，等它落盤。
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(
        bookDao.progressWrites,
        isNotEmpty,
        reason: 'runtime 級翻頁後進度必須寫入 DB（B7 回歸）',
      );
      expect(bookDao.progressWrites.last.chapterIndex, expected.chapterIndex);
      expect(bookDao.progressWrites.last.pos, expected.charOffset);
    });

    test('快速連續翻頁下視窗與位置保持一致', () async {
      final harness = makeRuntime([
        for (var i = 0; i < 4; i++) chapter(i, paragraphCount: 40),
      ]);
      final runtime = harness.runtime;
      addTearDown(runtime.dispose);
      await runtime.openBook();

      var lastChapter = runtime.state.visibleLocation.chapterIndex;
      var lastOffset = runtime.state.visibleLocation.charOffset;
      for (var step = 0; step < 60; step++) {
        final moved = runtime.moveToNextPage(saveSettledProgress: false);
        final location = runtime.state.visibleLocation;
        if (moved) {
          final advancedInChapter =
              location.chapterIndex == lastChapter &&
              location.charOffset > lastOffset;
          final advancedToNextChapter = location.chapterIndex > lastChapter;
          expect(
            advancedInChapter || advancedToNextChapter,
            isTrue,
            reason: '翻頁後位置必須前進（step $step）',
          );
          expect(
            runtime.state.pageWindow!.current.chapterIndex,
            location.chapterIndex,
          );
          lastChapter = location.chapterIndex;
          lastOffset = location.charOffset;
        } else {
          // 撞到尚未排版的相鄰章佔位頁：讓背景排版推進後繼續。
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      }
    });
  });
}
