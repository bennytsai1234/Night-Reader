import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_chapter_repository.dart';
import 'package:night_reader/features/reader_v2/hybrid/hybrid_reader_screen.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_style.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_progress_controller.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_runtime.dart';

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

/// 系統列內距改變只移動閱讀區上緣、不改排版時（例如從後台回到前台），
/// 文字必須留在畫面原位：捲動位置與閱讀區上緣同幅度移動。
void main() {
  const style = ReaderV2Style(
    fontSize: 18,
    lineHeight: 1.5,
    letterSpacing: 0,
    paragraphSpacing: 1.0,
    paddingTop: 0,
    paddingBottom: 0,
    paddingLeft: 12,
    paddingRight: 12,
  );

  ReaderV2Runtime makeRuntime(Size viewportSize) {
    final book = Book(
      bookUrl: 'http://book.test',
      name: '測試書',
      author: '作者',
      origin: 'local',
      originName: '本地',
    );
    final chapters = List.generate(
      3,
      (index) => BookChapter(
        url: 'chapter_$index',
        title: '第 $index 章',
        bookUrl: book.bookUrl,
        index: index,
        content: List.filled(40, '這是第 $index 章的一段測試正文。').join('\n'),
      ),
    );
    final bookDao = _FakeBookDao();
    final repository = ReaderV2ChapterRepository(
      book: book,
      initialChapters: chapters,
      bookDao: bookDao,
      chapterDao: _FakeChapterDao(),
      sourceDao: _FakeSourceDao(),
    );
    return ReaderV2Runtime(
      book: book,
      repository: repository,
      progressController: ReaderV2ProgressController(
        book: book,
        repository: repository,
        bookDao: bookDao,
      ),
      initialLayoutSpec: ReaderV2LayoutSpec.fromViewport(
        viewportSize: viewportSize,
        style: const ReaderV2LayoutStyle(
          fontSize: 18,
          lineHeight: 1.5,
          letterSpacing: 0,
          paragraphSpacing: 1.0,
          paddingTop: 0,
          paddingBottom: 0,
          paddingLeft: 12,
          paddingRight: 12,
        ),
      ),
      initialLocation: const ReaderV2Location(
        chapterIndex: 1,
        charOffset: 200,
      ),
    );
  }

  Widget host(ReaderV2Runtime runtime, double top) {
    return MaterialApp(
      home: Stack(
        children: [
          Positioned(
            top: top,
            left: 0,
            right: 0,
            bottom: 0,
            child: HybridReaderScreen(
              runtime: runtime,
              backgroundColor: Colors.white,
              textColor: Colors.black,
              style: style,
              viewportTop: top,
              enableDiskMetrics: false,
            ),
          ),
        ],
      ),
    );
  }

  testWidgets('text keeps its screen position when the viewport top moves', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const initialTop = 40.0;
    final runtime = makeRuntime(const Size(400, 800 - initialTop));
    addTearDown(runtime.dispose);

    await tester.pumpWidget(host(runtime, initialTop));
    var opened = false;
    runtime.openBook().whenComplete(() => opened = true);
    for (var i = 0; i < 200 && !opened; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(opened, isTrue);
    expect(runtime.pendingLocation, isNull);

    final position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    final before = position.pixels;

    // 內距暫時消失：閱讀區上緣往上移 40。
    await tester.pumpWidget(host(runtime, 0));
    expect(position.pixels, before - initialTop);

    // 內距恢復：回到原本的捲動位置。
    await tester.pumpWidget(host(runtime, initialTop));
    expect(position.pixels, before);
  });
}
