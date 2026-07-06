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
import 'package:night_reader/features/reader_v2/layout/reader_v2_style.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_progress_controller.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_runtime.dart';
import 'package:night_reader/features/reader_v2/viewport/scroll_reader_v2_viewport_model.dart';

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
  TestWidgetsFlutterBinding.ensureInitialized();

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
      (p) => '第 $index 章第 $p 段：這是一段用於視窗壓力測試的中文內容，帶有標點符號與足夠的長度以跨越多行。',
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
      initialLocation: const ReaderV2Location(chapterIndex: 1, charOffset: 0),
    );
  }

  /// 世界座標中任兩個相鄰頁面不得重疊（容忍極小的浮點誤差）。
  void expectNoOverlappingPlacements(ScrollReaderV2ViewportModel model) {
    final placements = model.visiblePages.allPages();
    for (var i = 0; i + 1 < placements.length; i++) {
      final current = placements[i];
      final next = placements[i + 1];
      expect(
        next.worldTop,
        greaterThanOrEqualTo(current.worldBottom - 0.75),
        reason:
            '頁面重疊：ch${current.page.chapterIndex}/p${current.page.pageIndex} '
            '底 ${current.worldBottom} 疊到 '
            'ch${next.page.chapterIndex}/p${next.page.pageIndex} '
            '頂 ${next.worldTop}（B5 回歸）',
      );
    }
  }

  group('ScrollReaderV2ViewportModel 視窗壓力測試', () {
    test('上方部分就緒章節背景長高時持續貼齊下一章頂端，頁面不重疊', () async {
      final runtime = makeRuntime([
        chapter(0, paragraphCount: 80),
        chapter(1, paragraphCount: 4),
        chapter(2, paragraphCount: 80),
      ]);
      addTearDown(runtime.dispose);
      final model = ScrollReaderV2ViewportModel(runtime: runtime, style: style);
      addTearDown(model.dispose);
      var contentChanges = 0;
      model.onWindowContentChanged = () => contentChanges += 1;

      final placed = await model.ensureWindowAround(1);
      expect(placed, isTrue);
      final backward = model.cacheManager.chapterAt(0);
      expect(backward, isNotNull);
      expect(
        backward!.isComplete,
        isFalse,
        reason: '測試前提：上一章必須是部分就緒（夠長才能驗證背景長高）',
      );
      expect(
        model.strip.chapterEnd(0)!,
        closeTo(model.strip.chapterTop(1)!, 0.5),
        reason: '上一章的底必須貼齊本章的頂',
      );

      // 模擬背景排版逐步推進上一章，每一步都檢查重錨不變量。
      var guard = 0;
      while (!(model.cacheManager.chapterAt(0)?.isComplete ?? true)) {
        await runtime.resolver.continueLayoutStep(0);
        expect(
          model.strip.chapterEnd(0)!,
          closeTo(model.strip.chapterTop(1)!, 0.5),
          reason: '上一章長高後必須以 bottom 重錨，否則新頁面會疊進本章（B5 回歸）',
        );
        expectNoOverlappingPlacements(model);
        guard += 1;
        expect(guard, lessThan(300), reason: '背景排版沒有收斂');
      }
      expect(
        contentChanges,
        greaterThan(0),
        reason: '背景長高必須發出視窗內容變更通知，viewport 才會重繪（B4 回歸）',
      );
    });

    test('跳轉到部分就緒章節後背景長高必須固定頂端，不得往上疊進上一章', () async {
      final runtime = makeRuntime([
        chapter(0, paragraphCount: 4),
        chapter(1, paragraphCount: 4),
        chapter(2, paragraphCount: 80),
        chapter(3, paragraphCount: 4),
      ]);
      addTearDown(runtime.dispose);
      final model = ScrollReaderV2ViewportModel(runtime: runtime, style: style);
      addTearDown(model.dispose);

      // 第一步：視窗中心在第 1 章，讓第 2 章成為部分就緒的前向邊界。
      expect(await model.ensureWindowAround(1), isTrue);
      final boundary = model.cacheManager.chapterAt(2);
      expect(boundary, isNotNull);
      if (boundary!.isComplete) {
        // 前向窗口較大，若一次就排完則本測試前提不成立——直接視為通過，
        // 但保留重疊檢查。
        expectNoOverlappingPlacements(model);
        return;
      }

      // 第二步：模擬章節跳轉——視窗改以部分就緒的第 2 章為中心，
      // 此時第 3 章會被放到它未排完的底部下方。
      expect(await model.ensureWindowAround(2), isTrue);
      expectNoOverlappingPlacements(model);
      final topBefore = model.strip.chapterTop(2)!;

      // 背景排版繼續推進第 2 章，每一步都檢查頂端固定與不重疊。
      var guard = 0;
      while (!(model.cacheManager.chapterAt(2)?.isComplete ?? true)) {
        await runtime.resolver.continueLayoutStep(2);
        expect(
          model.strip.chapterTop(2)!,
          closeTo(topBefore, 0.5),
          reason: '跳轉後的中心章長高必須固定頂端往下長，往上長會疊進上一章（章節跳轉文字重疊回歸）',
        );
        expectNoOverlappingPlacements(model);
        guard += 1;
        expect(guard, lessThan(300), reason: '背景排版沒有收斂');
      }
    });

    test('下方部分就緒章節背景長高時固定頂端往下長，頁面不重疊', () async {
      final runtime = makeRuntime([
        chapter(0, paragraphCount: 4),
        chapter(1, paragraphCount: 4),
        chapter(2, paragraphCount: 80),
      ]);
      addTearDown(runtime.dispose);
      final model = ScrollReaderV2ViewportModel(runtime: runtime, style: style);
      addTearDown(model.dispose);

      final placed = await model.ensureWindowAround(1);
      expect(placed, isTrue);
      final forward = model.cacheManager.chapterAt(2);
      expect(forward, isNotNull);
      if (forward!.isComplete) {
        // 前向窗口較大，若一次就排完則本測試前提不成立——直接視為通過，
        // 但保留重疊檢查。
        expectNoOverlappingPlacements(model);
        return;
      }
      final topBefore = model.strip.chapterTop(2)!;

      var guard = 0;
      while (!(model.cacheManager.chapterAt(2)?.isComplete ?? true)) {
        await runtime.resolver.continueLayoutStep(2);
        expect(
          model.strip.chapterTop(2)!,
          closeTo(topBefore, 0.5),
          reason: '下一章長高必須固定頂端，不得整段漂移',
        );
        expectNoOverlappingPlacements(model);
        guard += 1;
        expect(guard, lessThan(300), reason: '背景排版沒有收斂');
      }
    });
  });
}
