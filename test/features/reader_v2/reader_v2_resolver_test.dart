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
import 'package:night_reader/features/reader_v2/session/reader_v2_resolver.dart';

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
      '這是一段用來測試漸進式排版的中文內容，包含標點符號與足夠長度以便跨越多個頁面。',
    ).join('\n\n');
    return BookChapter(
      url: 'chapter_$index',
      title: '第 $index 章',
      bookUrl: 'http://book.test',
      index: index,
      content: body,
    );
  }

  BookChapter shortChapter(int index) {
    return BookChapter(
      url: 'chapter_$index',
      title: '第 $index 章',
      bookUrl: 'http://book.test',
      index: index,
      content: '這是一段很短的內容。',
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

  group('ReaderV2Resolver.ensureLayoutAtLeast', () {
    test('只做剛好夠用的工作量就回傳，不必排完整章', () async {
      final resolver = makeResolver([longChapter(0)]);
      final content = await resolver.repository.loadContent(0);
      final fullReference = await ReaderV2LayoutEngine().layout(
        content,
        resolver.layoutSpec,
      );

      final partial = await resolver.ensureLayoutAtLeast(0, minExtentPx: 80);

      expect(partial.isComplete, isFalse);
      expect(partial.contentHeight, lessThan(fullReference.contentHeight));
      expect(partial.pages.length, lessThan(fullReference.pages.length));
      expect(partial.pages.last.isChapterEnd, isFalse);
    });

    test('多次呼叫最終會排完整章，且與一次到位的結果一致', () async {
      final resolver = makeResolver([longChapter(0)]);
      final content = await resolver.repository.loadContent(0);
      final fullReference = await ReaderV2LayoutEngine().layout(
        content,
        resolver.layoutSpec,
      );

      var view = await resolver.ensureLayoutAtLeast(0, minExtentPx: 80);
      var iterations = 0;
      while (!view.isComplete) {
        final before = view.contentHeight;
        view = await resolver.ensureLayoutAtLeast(0, minExtentPx: before + 80);
        expect(
          view.contentHeight,
          greaterThanOrEqualTo(before),
          reason: '每次續跑內容高度只能增加，不能倒退',
        );
        iterations += 1;
        expect(iterations, lessThan(1000), reason: '避免測試因邏輯錯誤卡在無限迴圈');
      }

      expect(view.isComplete, isTrue);
      expect(view.pages.length, fullReference.pages.length);
      expect(view.contentHeight, fullReference.contentHeight);
      expect(view.pages.last.isChapterEnd, isTrue);
      expect(iterations, greaterThan(1), reason: '這個測試要驗證的就是多次續跑才排完');
    });

    test('minExtentPx 為 double.infinity 時等同排完整章（既有 ensureLayout 行為）', () async {
      final resolver = makeResolver([longChapter(0)]);
      final view = await resolver.ensureLayout(0);

      expect(view.isComplete, isTrue);
      expect(view.pages.last.isChapterEnd, isTrue);
    });

    test('onChapterProgressed 在每次寫入快取（部分或完整）都會觸發', () async {
      final resolver = makeResolver([longChapter(0)]);
      final progressed = <int>[];
      resolver.onChapterProgressed = progressed.add;

      var view = await resolver.ensureLayoutAtLeast(0, minExtentPx: 80);
      expect(progressed, contains(0));
      final firstCount = progressed.length;

      while (!view.isComplete) {
        view = await resolver.ensureLayoutAtLeast(
          0,
          minExtentPx: view.contentHeight + 80,
        );
      }
      expect(progressed.length, greaterThan(firstCount));
      expect(progressed.every((index) => index == 0), isTrue);
    });

    test('章節內容很短時第一次呼叫就直接完成', () async {
      final resolver = makeResolver([shortChapter(0)]);
      final view = await resolver.ensureLayoutAtLeast(0, minExtentPx: 1);

      expect(view.isComplete, isTrue);
      expect(view.pages.last.isChapterEnd, isTrue);
    });
  });

  group('ReaderV2Resolver 同章未完成 vs 真正章節結尾', () {
    test('nextPageSync 在本章排版未完成時回傳本章 loading 佔位頁，不誤跳下一章', () async {
      final resolver = makeResolver([longChapter(0), shortChapter(1)]);
      final partial = await resolver.ensureLayoutAtLeast(0, minExtentPx: 80);
      expect(partial.isComplete, isFalse);

      final lastAvailablePage = partial.pages.last;
      final next = resolver.nextPageSync(lastAvailablePage);

      expect(next, isNotNull);
      expect(next!.isPlaceholder, isTrue);
      expect(next.isLoading, isTrue);
      expect(next.chapterIndex, 0, reason: '應該是本章的佔位頁，不是跳去下一章');
    });

    test('nextPageSync 在本章真正排完時才會接到下一章第一頁', () async {
      final resolver = makeResolver([shortChapter(0), shortChapter(1)]);
      final chapter0 = await resolver.ensureLayout(0);
      final chapter1 = await resolver.ensureLayout(1);
      expect(chapter0.isComplete, isTrue);

      final next = resolver.nextPageSync(chapter0.pages.last);

      expect(next, isNotNull);
      expect(next!.isPlaceholder, isFalse);
      expect(next.chapterIndex, 1);
      expect(next.startCharOffset, chapter1.pages.first.startCharOffset);
    });

    test(
      'prevPageSync 在前一章排版未完成時回傳前一章 loading 佔位頁，不誤用未完成的 pages.last',
      () async {
        final resolver = makeResolver([longChapter(0), shortChapter(1)]);
        await resolver.ensureLayoutAtLeast(0, minExtentPx: 80);
        final chapter1 = await resolver.ensureLayout(1);

        final prev = resolver.prevPageSync(chapter1.pages.first);

        expect(prev, isNotNull);
        expect(prev!.isPlaceholder, isTrue);
        expect(prev.isLoading, isTrue);
        expect(prev.chapterIndex, 0);
      },
    );

    test('prevPageSync 在前一章真正排完時才會接到它的最後一頁', () async {
      final resolver = makeResolver([shortChapter(0), shortChapter(1)]);
      final chapter0 = await resolver.ensureLayout(0);
      final chapter1 = await resolver.ensureLayout(1);

      final prev = resolver.prevPageSync(chapter1.pages.first);

      expect(prev, isNotNull);
      expect(prev!.isPlaceholder, isFalse);
      expect(prev.chapterIndex, 0);
      expect(prev.startCharOffset, chapter0.pages.last.startCharOffset);
    });
  });
}
