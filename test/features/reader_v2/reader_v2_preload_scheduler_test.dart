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
import 'package:night_reader/features/reader_v2/runtime/reader_v2_preload_scheduler.dart';
import 'package:night_reader/features/reader_v2/runtime/reader_v2_resolver.dart';

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

  BookChapter longChapter(int index, {int paragraphCount = 60}) {
    final body = List<String>.filled(
      paragraphCount,
      '這是一段用來測試背景排版輪流推進的中文內容，包含標點符號與足夠長度以便跨越多個頁面。',
    ).join('\n\n');
    return BookChapter(
      url: 'chapter_$index',
      title: '第 $index 章',
      bookUrl: 'http://book.test',
      index: index,
      content: body,
    );
  }

  ReaderV2Resolver makeResolver(List<BookChapter> chapters) {
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
    return ReaderV2Resolver(
      repository: repository,
      layoutEngine: ReaderV2LayoutEngine(),
      layoutSpec: spec(),
    );
  }

  group('ReaderV2PreloadScheduler.scheduleLayout', () {
    test('部分就緒的快取不會被誤判為已完成而跳過', () async {
      final resolver = makeResolver([longChapter(0)]);
      final scheduler = ReaderV2PreloadScheduler(resolver: resolver);
      addTearDown(scheduler.dispose);

      final partial = await resolver.ensureLayoutAtLeast(0, minExtentPx: 80);
      expect(partial.isComplete, isFalse);

      await scheduler.scheduleLayout(0);

      expect(resolver.cachedLayout(0)!.isComplete, isTrue);
    });

    test('scheduleLayout 回傳的 Future 要排完整章才算完成', () async {
      final resolver = makeResolver([longChapter(0)]);
      final scheduler = ReaderV2PreloadScheduler(resolver: resolver);
      addTearDown(scheduler.dispose);

      await scheduler.scheduleLayout(0);

      expect(resolver.cachedLayout(0), isNotNull);
      expect(resolver.cachedLayout(0)!.isComplete, isTrue);
    });

    test('已完成的章節會被跳過，不重新觸發排版', () async {
      final resolver = makeResolver([longChapter(0)]);
      final scheduler = ReaderV2PreloadScheduler(resolver: resolver);
      addTearDown(scheduler.dispose);

      await resolver.ensureLayout(0);
      final progressed = <int>[];
      resolver.onChapterProgressed = progressed.add;

      await scheduler.scheduleLayout(0);

      expect(progressed, isEmpty, reason: '已完成的章節不該再觸發任何排版工作');
    });

    test('多個排隊中的長章節會輪流推進，不是先做完第一個才輪到下一個', () async {
      final resolver = makeResolver([longChapter(0), longChapter(1)]);
      final scheduler = ReaderV2PreloadScheduler(resolver: resolver);
      addTearDown(scheduler.dispose);

      final progressed = <int>[];
      resolver.onChapterProgressed = progressed.add;

      final done = Future.wait([
        scheduler.scheduleLayout(0),
        scheduler.scheduleLayout(1),
      ]);
      await done;

      expect(resolver.cachedLayout(0)!.isComplete, isTrue);
      expect(resolver.cachedLayout(1)!.isComplete, isTrue);
      expect(progressed.length, greaterThan(2), reason: '兩章都要跑好幾個 step 才排得完');

      // 找出章節 0 最後一次進度事件之前，章節 1 是否已經開始有進度——
      // 如果是先把章節 0 整個做完才輪到章節 1，章節 1 只會在最後才出現。
      final lastChapter0Index = progressed.lastIndexOf(0);
      final firstChapter1Index = progressed.indexOf(1);
      expect(
        firstChapter1Index,
        lessThan(lastChapter0Index),
        reason: '章節 1 應該在章節 0 排完之前就已經開始輪流推進',
      );
    });
  });
}
