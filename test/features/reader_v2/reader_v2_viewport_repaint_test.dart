import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_chapter_repository.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_engine.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_style.dart';
import 'package:night_reader/features/reader_v2/render/reader_v2_tile_painter.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_progress_controller.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_runtime.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_state.dart';
import 'package:night_reader/features/reader_v2/viewport/reader_v2_viewport_controller.dart';
import 'package:night_reader/features/reader_v2/viewport/scroll_reader_v2_viewport.dart';

class _FakeBookDao extends Fake implements BookDao {
  @override
  Future<void> updateProgress(
    String bookUrl,
    int chapterIndex,
    String chapterTitle,
    int pos, {
    double visualOffsetPx = 0.0,
    String? readerAnchorJson,
  }) async {}
}

class _FakeChapterDao extends Fake implements ChapterDao {}

class _FakeSourceDao extends Fake implements BookSourceDao {}

void main() {
  const style = ReaderV2Style(
    fontSize: 18,
    lineHeight: 1.5,
    letterSpacing: 0,
    paragraphSpacing: 0.8,
    paddingTop: 12,
    paddingBottom: 12,
    paddingLeft: 12,
    paddingRight: 12,
    textIndent: 2,
  );

  ReaderV2LayoutSpec spec() {
    return ReaderV2LayoutSpec.fromViewport(
      viewportSize: const Size(220, 180),
      style: const ReaderV2LayoutStyle(
        fontSize: 18,
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

  BookChapter chapter(int index, {required int paragraphCount}) {
    final body = List<String>.generate(
      paragraphCount,
      (p) => '第 $index 章第 $p 段：這是一段用於視埠重繪回歸測試的中文內容，帶有標點符號與足夠的長度以跨越多行。',
    ).join('\n\n');
    return BookChapter(
      url: 'chapter_$index',
      title: '第 $index 章',
      bookUrl: 'http://book.test',
      index: index,
      content: body,
    );
  }

  ReaderV2Runtime makeRuntime(List<BookChapter> chapters) {
    final book = Book(
      bookUrl: 'http://book.test',
      name: '測試書',
      author: '作者',
      origin: 'local',
      originName: '本地',
    );
    final repository = ReaderV2ChapterRepository(
      book: book,
      initialChapters: chapters,
      bookDao: _FakeBookDao(),
      chapterDao: _FakeChapterDao(),
      sourceDao: _FakeSourceDao(),
    );
    return ReaderV2Runtime(
      book: book,
      repository: repository,
      layoutEngine: ReaderV2LayoutEngine(),
      progressController: ReaderV2ProgressController(
        book: book,
        repository: repository,
        bookDao: _FakeBookDao(),
      ),
      initialLayoutSpec: spec(),
      initialLocation: const ReaderV2Location(chapterIndex: 0, charOffset: 0),
    );
  }

  Future<void> pumpViewport(
    WidgetTester tester,
    ReaderV2Runtime runtime,
    ReaderV2ViewportController controller,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 220,
            height: 180,
            child: ScrollReaderV2Viewport(
              runtime: runtime,
              backgroundColor: const Color(0xFFFFFFFF),
              textColor: const Color(0xFF000000),
              style: style,
              controller: controller,
            ),
          ),
        ),
      ),
    );
  }

  /// 在 fake-async 測試環境下等待 future：排版引擎的 8ms yield 走
  /// `Future.delayed`（計時器），不 pump 的話 bare await 會永遠卡住。
  Future<T> awaitWithPumps<T>(WidgetTester tester, Future<T> future) async {
    T? result;
    Object? error;
    var done = false;
    unawaited(
      future.then(
        (value) {
          result = value;
          done = true;
        },
        onError: (Object e) {
          error = e;
          done = true;
        },
      ),
    );
    for (var i = 0; i < 4000 && !done; i++) {
      await tester.pump(const Duration(milliseconds: 4));
    }
    if (error != null) throw error!;
    expect(done, isTrue, reason: '等待的非同步作業未在時限內完成');
    return result as T;
  }

  Future<void> pumpUntilReady(
    WidgetTester tester,
    ReaderV2Runtime runtime,
  ) async {
    for (var i = 0; i < 400; i++) {
      if (runtime.state.phase == ReaderV2Phase.ready) break;
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(runtime.state.phase, ReaderV2Phase.ready, reason: '開書未達 ready');
    // 讓 ready 後排定的 post-frame 工作（初始跳轉、首繪）跑完。
    for (var i = 0; i < 40 && tester.binding.hasScheduledFrame; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  group('ScrollReaderV2Viewport 重繪回歸', () {
    final painted = <String>[];

    setUp(() {
      painted.clear();
      ReaderV2TilePainter.debugOnPaint =
          (tile) => painted.add('${tile.chapterIndex}:${tile.pageIndex}');
    });

    tearDown(() {
      ReaderV2TilePainter.debugOnPaint = null;
    });

    testWidgets('連續捲動跨頁時，同一 tile 不得重繪第二次', (tester) async {
      final runtime = makeRuntime([
        chapter(0, paragraphCount: 40),
        chapter(1, paragraphCount: 4),
        chapter(2, paragraphCount: 4),
      ]);
      // 固定背景排版暫停，避免排程器在測試中途推進造成不確定性。
      runtime.beginInteractivePreloadPause();
      final controller = ReaderV2ViewportController();
      await pumpViewport(tester, runtime, controller);
      unawaited(runtime.openBook());
      await pumpUntilReady(tester, runtime);

      painted.clear();
      for (var i = 0; i < 6; i++) {
        final moved = await controller.scrollBy!(60);
        expect(moved, isTrue, reason: '第 ${i + 1} 次捲動沒有位移');
        await tester.pump();
        await tester.pump();
      }

      final counts = <String, int>{};
      for (final key in painted) {
        counts[key] = (counts[key] ?? 0) + 1;
      }
      final repainted =
          counts.entries.where((entry) => entry.value > 1).toList();
      expect(
        repainted,
        isEmpty,
        reason:
            '可見頁集合位移時既有 tile 不得重繪（Positioned 未帶 key 會讓 '
            'RepaintBoundary 整批重建）：$counts',
      );

      await tester.pumpWidget(const SizedBox());
      runtime.dispose();
    });

    testWidgets('部分就緒章節背景排版推進時，內容未變的可見 tile 不得重繪', (tester) async {
      final runtime = makeRuntime([
        chapter(0, paragraphCount: 16),
        chapter(1, paragraphCount: 400),
        chapter(2, paragraphCount: 4),
      ]);
      runtime.beginInteractivePreloadPause();
      final controller = ReaderV2ViewportController();
      await pumpViewport(tester, runtime, controller);
      unawaited(runtime.openBook());
      await pumpUntilReady(tester, runtime);

      // 前提：下一章夠長，開書時只部分就緒。
      final forwardLayout = runtime.resolver.cachedLayout(1);
      expect(forwardLayout, isNotNull, reason: '前向視窗應已放入下一章');
      if (forwardLayout!.isComplete) {
        // 一次就排完則本測試前提不成立，直接結束（同視窗壓力測試的做法）。
        await tester.pumpWidget(const SizedBox());
        runtime.dispose();
        return;
      }

      // 往下捲到下一章第一頁剛進入視野（停在本章結尾前 100px：下一章頂端
      // 露出視窗底部約 80px，而 capture anchor（36px）仍留在本章，避免
      // 視窗移中心把下一章整章排完）。
      final chapter0Height =
          runtime.resolver.cachedLayout(0)!.contentHeight;
      await awaitWithPumps(tester, controller.scrollBy!(chapter0Height - 100));
      await tester.pump();
      expect(
        painted.contains('1:0'),
        isTrue,
        reason: '下一章第一頁未進入視野（chapter0Height=$chapter0Height）',
      );
      if (runtime.resolver.cachedLayout(1)?.isComplete ?? true) {
        await tester.pumpWidget(const SizedBox());
        runtime.dispose();
        return;
      }

      painted.clear();
      for (var step = 0; step < 3; step++) {
        await awaitWithPumps(tester, runtime.resolver.continueLayoutStep(1));
        await tester.pump();
        await tester.pump();
        if (runtime.resolver.cachedLayout(1)?.isComplete ?? true) break;
      }

      final unexpected =
          painted
              .where((key) => key == '1:0' || key.startsWith('0:'))
              .toList();
      expect(
        unexpected,
        isEmpty,
        reason:
            '背景排版推進只重新包裝章節頁面，內容未變的可見 tile 不得重繪'
            '（shouldRepaint 比到 pageSize 等非繪製欄位會整章重繪）：$painted',
      );

      await tester.pumpWidget(const SizedBox());
      runtime.dispose();
    });

    testWidgets('甩動減速期間 runtime notify 受節流約束，settle 後進度落地', (tester) async {
      final runtime = makeRuntime([
        chapter(0, paragraphCount: 60),
        chapter(1, paragraphCount: 4),
        chapter(2, paragraphCount: 4),
      ]);
      runtime.beginInteractivePreloadPause();
      final controller = ReaderV2ViewportController();
      await pumpViewport(tester, runtime, controller);
      unawaited(runtime.openBook());
      await pumpUntilReady(tester, runtime);

      var notifies = 0;
      runtime.addListener(() => notifies += 1);

      await tester.fling(
        find.byType(ScrollReaderV2Viewport),
        const Offset(0, -300),
        2500,
      );
      var frames = 0;
      while (tester.binding.hasScheduledFrame && frames < 600) {
        await tester.pump(const Duration(milliseconds: 16));
        frames += 1;
      }
      expect(frames, lessThan(600), reason: '甩動動畫未收斂');

      expect(
        notifies,
        lessThan(20),
        reason:
            '拖曳/甩動期間 capture 應節流 notify（每 2 tick 全頁重建即為'
            '放開後卡頓的來源之一），實際 $notifies 次',
      );
      final location = runtime.state.visibleLocation;
      expect(
        location.chapterIndex > 0 || location.charOffset > 0,
        isTrue,
        reason: 'settle 後 visibleLocation 應反映甩動後的位置',
      );

      await tester.pumpWidget(const SizedBox());
      runtime.dispose();
    });
  });
}
