// 閱讀器跳章：從開始跳到正文出來、紙掀開的每一幀成本（ADR 0018）。用法見
// `test/support/frame_budget.dart`；帶 `frame_budget` 標籤，平常的全套測試
// 跳過。
//
// 正文直接從記憶體給（不經資料庫與內容轉換 worker），換行預處理也在原地
// 做（`TextPreprocessor(useIsolate: false)`，App 裡在背景）：量的是閱讀器
// 自己的排版與畫面。
@Tags(['frame_budget'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_chapter_repository.dart';
import 'package:night_reader/features/reader_v2/hybrid/hybrid_reader_screen.dart';
import 'package:night_reader/features/reader_v2/hybrid/text/text_preprocessor.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_style.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_progress_controller.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_runtime.dart';
import 'package:night_reader/features/reader_v2/viewport/reader_v2_viewport_controller.dart';

import '../support/frame_budget.dart';

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

class _FakeChapterDao extends Fake implements ChapterDao {
  @override
  Future<int?> indexOfUrl(String bookUrl, String url) async => null;

  @override
  Future<T> transaction<T>(
    Future<T> Function() action, {
    bool requireNew = false,
  }) => action();
}

class _FakeSourceDao extends Fake implements BookSourceDao {}

const Size _viewport = Size(400, 800);

const ReaderV2Style _style = ReaderV2Style(
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

/// 一章約七千字，網路小說常見的長度。
BookChapter _chapter(int index) => BookChapter(
  url: 'chapter_$index',
  title: '第 $index 章',
  bookUrl: 'http://frame-budget.test',
  index: index,
  content: List<String>.generate(
    120,
    (p) =>
        '第 $index 章第 $p 段，夜深人靜時翻開書頁，字句在燈下慢慢展開，'
        '「你說呢？」他問。風從窗外吹進來，紙頁輕輕翻動。',
  ).join('\n'),
);

void main() {
  testWidgets('jumping to a chapter until its text shows', (tester) async {
    tester.view.physicalSize = _viewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final book = Book(
      bookUrl: 'http://frame-budget.test',
      name: '量測',
      author: '作者',
      origin: 'local',
      originName: '本地',
    );
    final bookDao = _FakeBookDao();
    final repository = ReaderV2ChapterRepository(
      book: book,
      initialChapters: List<BookChapter>.generate(40, _chapter),
      contentLoader: (_, chapter) => Future<String?>.value(chapter.content),
      bookDao: bookDao,
      chapterDao: _FakeChapterDao(),
      sourceDao: _FakeSourceDao(),
    );
    final runtime = ReaderV2Runtime(
      book: book,
      repository: repository,
      progressController: ReaderV2ProgressController(
        book: book,
        repository: repository,
        bookDao: bookDao,
      ),
      initialLayoutSpec: ReaderV2LayoutSpec.fromViewport(
        viewportSize: _viewport,
        style: ReaderV2LayoutStyle(
          fontSize: _style.fontSize,
          lineHeight: _style.lineHeight,
          letterSpacing: _style.letterSpacing,
          paragraphSpacing: _style.paragraphSpacing,
          paddingTop: _style.paddingTop,
          paddingBottom: _style.paddingBottom,
          paddingLeft: _style.paddingLeft,
          paddingRight: _style.paddingRight,
          textIndent: _style.textIndent,
        ),
      ),
      initialLocation: const ReaderV2Location(chapterIndex: 3, charOffset: 0),
    );
    addTearDown(runtime.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: HybridReaderScreen(
          runtime: runtime,
          backgroundColor: Colors.white,
          textColor: Colors.black,
          style: _style,
          viewportController: ReaderV2ViewportController(),
          enableDiskCache: false,
          preprocessor: const TextPreprocessor(useIsolate: false),
        ),
      ),
    );
    unawaited(runtime.openBook());
    for (var f = 0; f < 3000 && !runtime.state.hasStableWorld; f++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    // 開書的紙掀完、前後章排好。
    for (var f = 0; f < 200; f++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    // 第一次跳章含程式第一次執行的成本，連跳三次看穩定的樣子。
    for (final target in [20, 30, 10]) {
      unawaited(runtime.jumpToChapter(target));
      final costs = await recordFrames(
        tester,
        until: () => runtime.stateMachine.currentOperation == null,
        // 紙掀開的淡出也算在內。
        tailFrames: 40,
      );
      // ignore: avoid_print
      print(describeFrames('跳到第 $target 章', costs));
      expect(runtime.state.visibleLocation.chapterIndex, target);
    }
  });
}
