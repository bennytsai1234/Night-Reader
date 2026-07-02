import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_chapter_repository.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_content.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_engine.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_chapter_view.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_resolver.dart';

class _FakeBookDao extends Fake implements BookDao {}

class _FakeChapterDao extends Fake implements ChapterDao {}

class _FakeSourceDao extends Fake implements BookSourceDao {}

/// 指定章節可以人工切換載入失敗，用來驗證排版錯誤的記錄與清除。
class _FlakyRepository extends ReaderV2ChapterRepository {
  _FlakyRepository({
    required super.book,
    super.initialChapters,
    super.bookDao,
    super.chapterDao,
    super.sourceDao,
  });

  final Set<int> failingChapters = <int>{};

  @override
  Future<ReaderV2Content> loadContent(int chapterIndex) {
    if (failingChapters.contains(chapterIndex)) {
      throw const ReaderV2ChapterRepositoryException('模擬章節載入失敗');
    }
    return super.loadContent(chapterIndex);
  }
}

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

  BookChapter chapter(int index, {int paragraphCount = 20}) {
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

  _FlakyRepository makeRepository(List<BookChapter> chapters) {
    final book = Book(
      bookUrl: 'http://book.test',
      name: '測試書',
      author: '作者',
      origin: 'local',
      originName: '本地',
    );
    return _FlakyRepository(
      book: book,
      initialChapters: chapters,
      bookDao: _FakeBookDao(),
      chapterDao: _FakeChapterDao(),
      sourceDao: _FakeSourceDao(),
    );
  }

  /// 驗證排版結果沒有重複排入內容：非空行的字元起點必須單調不減。
  void expectMonotonicLines(ReaderV2ChapterView view) {
    var lastStart = -1;
    var lastTop = double.negativeInfinity;
    for (final line in view.lines) {
      if (line.text.isEmpty) continue;
      expect(
        line.startCharOffset,
        greaterThanOrEqualTo(lastStart),
        reason: '行字元起點倒退，代表章節內容被重複排版',
      );
      expect(
        line.top,
        greaterThanOrEqualTo(lastTop),
        reason: '行位置倒退，代表排版累積快照被污染',
      );
      lastStart = line.startCharOffset;
      lastTop = line.top;
    }
  }

  group('ReaderV2Resolver 壓力測試', () {
    test('併發 ensureLayoutAtLeast × updateLayoutSpec 轟炸後結果一致且無重複內容', () async {
      final repository = makeRepository([
        for (var i = 0; i < 6; i++) chapter(i),
      ]);
      final resolver = ReaderV2Resolver(
        repository: repository,
        layoutEngine: ReaderV2LayoutEngine(),
        layoutSpec: specWithFontSize(18),
      );

      final futures = <Future<ReaderV2ChapterView>>[
        for (var i = 0; i < 6; i++)
          resolver.ensureLayoutAtLeast(i, minExtentPx: 600),
      ];
      // 排版進行中反覆切換 spec，模擬使用者連續調整字級。
      for (var flip = 0; flip < 6; flip++) {
        await Future<void>.delayed(Duration.zero);
        resolver.updateLayoutSpec(specWithFontSize(flip.isEven ? 22 : 18));
      }
      final views = await Future.wait(futures).timeout(
        const Duration(seconds: 60),
        onTimeout: () => fail('ensureLayoutAtLeast 在 spec 轟炸下沒有收斂'),
      );

      final validSignatures = <int>{
        specWithFontSize(18).layoutSignature,
        specWithFontSize(22).layoutSignature,
      };
      for (final view in views) {
        expect(validSignatures, contains(view.layoutSignature));
        expectMonotonicLines(view);
      }

      // 轟炸結束後，最終快取必須收斂到目前 spec 並可排完整章。
      final settled = await resolver.ensureLayout(0);
      expect(settled.layoutSignature, resolver.layoutSpec.layoutSignature);
      expect(settled.isComplete, isTrue);
      expectMonotonicLines(settled);
    });

    test('retainLayoutsFor 與 ensureLayout 併發不會讓結果卡死或損壞', () async {
      final repository = makeRepository([
        for (var i = 0; i < 8; i++) chapter(i, paragraphCount: 10),
      ]);
      final resolver = ReaderV2Resolver(
        repository: repository,
        layoutEngine: ReaderV2LayoutEngine(),
        layoutSpec: specWithFontSize(18),
      );

      final futures = <Future<ReaderV2ChapterView>>[
        for (var i = 0; i < 8; i++) resolver.ensureLayout(i),
      ];
      for (var round = 0; round < 8; round++) {
        await Future<void>.delayed(Duration.zero);
        resolver.retainLayoutsFor(<int>{round, round + 1});
      }
      final views = await Future.wait(futures).timeout(
        const Duration(seconds: 60),
        onTimeout: () => fail('retainLayoutsFor 轟炸下 ensureLayout 沒有收斂'),
      );
      for (final view in views) {
        expect(view.isComplete, isTrue);
        expectMonotonicLines(view);
      }
    });

    test('排版錯誤在 updateLayoutSpec 後必須清除，不得殘留舊錯誤', () async {
      final repository = makeRepository([chapter(0), chapter(1)]);
      final resolver = ReaderV2Resolver(
        repository: repository,
        layoutEngine: ReaderV2LayoutEngine(),
        layoutSpec: specWithFontSize(18),
      );

      repository.failingChapters.add(1);
      await expectLater(
        resolver.ensureLayoutAtLeast(1, minExtentPx: 100, retryOnStale: false),
        throwsA(isA<ReaderV2ChapterRepositoryException>()),
      );
      expect(
        resolver.placeholderPageFor(1).errorMessage,
        isNotNull,
        reason: '載入失敗後佔位頁應顯示錯誤',
      );

      // 換 spec（等同使用者調整字級）後，舊 spec 的錯誤不得殘留。
      resolver.updateLayoutSpec(specWithFontSize(22));
      final placeholder = resolver.placeholderPageFor(1);
      expect(
        placeholder.errorMessage,
        isNull,
        reason: '更換排版 spec 後殘留舊排版錯誤（B3 回歸）',
      );
      expect(placeholder.isLoading, isTrue);

      // 章節恢復正常後要能排完。
      repository.failingChapters.clear();
      final view = await resolver.ensureLayout(1);
      expect(view.isComplete, isTrue);
      expect(resolver.placeholderPageFor(0).errorMessage, isNull);
    });
  });
}
