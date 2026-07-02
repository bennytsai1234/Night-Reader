import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/features/reader_v2/content/reader_v2_chapter_repository.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_engine.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';
import 'package:night_reader/features/reader_v2/runtime/reader_v2_progress_controller.dart';
import 'package:night_reader/features/reader_v2/runtime/reader_v2_runtime.dart';
import 'package:night_reader/features/reader_v2/viewport/reader_v2_chapter_page_cache_manager.dart';

class _FakeBookDao extends Fake implements BookDao {}

class _FakeChapterDao extends Fake implements ChapterDao {}

class _FakeSourceDao extends Fake implements BookSourceDao {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  BookChapter chapter(int index, {int paragraphCount = 3}) {
    final body = List<String>.filled(
      paragraphCount,
      '這是一段用來測試視窗建置的中文內容，包含標點符號與足夠長度以便跨越多個頁面。',
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
    );
  }

  ReaderV2ChapterPageCacheManager makeManager(List<BookChapter> chapters) {
    final runtime = makeRuntime(chapters);
    return ReaderV2ChapterPageCacheManager(
      runtime: runtime,
      pageExtent: (page) => page.contentHeight,
    );
  }

  group('ReaderV2ChapterPageCacheManager.ensureWindowAround', () {
    test('撞上超長下一章時，等待時間只跟視窗需求成正比，不必排完整章才回傳', () async {
      final manager = makeManager([
        chapter(0),
        chapter(1, paragraphCount: 400), // 刻意做得非常長
      ]);

      final window = await manager.ensureWindowAround(
        centerChapterIndex: 0,
        backwardExtent: 100,
        forwardExtent: 200, // 遠小於整章長度
      );

      expect(window, isNotNull);
      final nextChapter = manager.chapterAt(1);
      expect(nextChapter, isNotNull);
      expect(
        nextChapter!.isComplete,
        isFalse,
        reason: '只需要 200px 的視窗需求，不該把超長章節整章排完',
      );
      expect(nextChapter.extent, lessThan(5000));
    });

    test('未完成的邊界章節不會讓迴圈跳去抓更遠一章', () async {
      final manager = makeManager([
        chapter(0),
        chapter(1, paragraphCount: 400),
        chapter(2),
      ]);

      await manager.ensureWindowAround(
        centerChapterIndex: 0,
        backwardExtent: 100,
        forwardExtent: 200,
      );

      expect(manager.chapterAt(1), isNotNull);
      expect(manager.chapterAt(1)!.isComplete, isFalse);
      expect(
        manager.chapterAt(2),
        isNull,
        reason: '章節 1 還沒排完，不該再往前抓章節 2',
      );
    });

    test('視窗涵蓋範圍夠大時，章節仍會排完整章（既有行為不受影響）', () async {
      final manager = makeManager([chapter(0), chapter(1, paragraphCount: 2)]);

      await manager.ensureWindowAround(
        centerChapterIndex: 0,
        backwardExtent: 100,
        forwardExtent: 10000,
      );

      expect(manager.chapterAt(1), isNotNull);
      expect(manager.chapterAt(1)!.isComplete, isTrue);
    });
  });

  group('ReaderV2ChapterPageCacheManager 背景排版進度通知', () {
    test('已放進視窗的部分就緒章節，背景排版繼續推進時會自動更新且 bump revision', () async {
      final manager = makeManager([
        chapter(0),
        chapter(1, paragraphCount: 400),
      ]);

      await manager.ensureWindowAround(
        centerChapterIndex: 0,
        backwardExtent: 100,
        forwardExtent: 200,
      );
      final beforeExtent = manager.chapterAt(1)!.extent;
      final beforeRevision = manager.revision;

      // 模擬背景排程器在使用者沒有再滑動的情況下，繼續把章節 1 往後排。
      await manager.runtime.resolver.ensureLayoutAtLeast(
        1,
        minExtentPx: beforeExtent + 2000,
      );

      expect(manager.chapterAt(1)!.extent, greaterThan(beforeExtent));
      expect(manager.revision, greaterThan(beforeRevision));
    });

    test('背景排版進度屬於不在視窗內的章節時，不影響 manager 快取', () async {
      final manager = makeManager([
        chapter(0),
        chapter(1, paragraphCount: 3),
        chapter(2, paragraphCount: 3),
      ]);

      await manager.ensureWindowAround(
        centerChapterIndex: 0,
        backwardExtent: 100,
        forwardExtent: 100,
      );
      expect(manager.chapterAt(2), isNull, reason: '章節 2 一開始不該在視窗內');
      final beforeRevision = manager.revision;

      // 模擬某個跟目前視窗無關的背景流程（例如 TTS 預先取用）直接對章節 2
      // 觸發排版，不透過 manager。manager 不該因此誤把它算進快取。
      await manager.runtime.resolver.ensureLayoutAtLeast(2, minExtentPx: 1);

      expect(manager.chapterAt(2), isNull);
      expect(manager.revision, beforeRevision);
    });
  });
}
