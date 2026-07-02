import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/content/reader_v2_content.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_engine.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ReaderV2LayoutSpec spec({
    Size viewport = const Size(220, 180),
    double fontSize = 18,
    double letterSpacing = 0,
  }) {
    return ReaderV2LayoutSpec.fromViewport(
      viewportSize: viewport,
      style: ReaderV2LayoutStyle(
        fontSize: fontSize,
        lineHeight: 1.5,
        letterSpacing: letterSpacing,
        paragraphSpacing: 0.8,
        paddingTop: 12,
        paddingBottom: 12,
        paddingLeft: 12,
        paddingRight: 12,
        textIndent: 2,
      ),
    );
  }

  group('ReaderV2LayoutEngine', () {
    test('cuts text into monotonic lines and paginates long chapters', () async {
      final content = ReaderV2Content.fromRaw(
        chapterIndex: 0,
        title: '第一章 測試',
        rawText: List<String>.filled(
          18,
          '這是一段用來測試排版切行與分頁的中文內容，包含標點符號與足夠長度。',
        ).join('\n\n'),
      );
      final layout = await ReaderV2LayoutEngine().layout(content, spec());

      expect(layout.lines, isNotEmpty);
      expect(layout.pages.length, greaterThan(1));
      expect(layout.pages.first.isChapterStart, isTrue);
      expect(layout.pages.last.isChapterEnd, isTrue);

      var previousTop = -1.0;
      var previousOffset = -1;
      for (final line in layout.lines) {
        expect(line.top, greaterThanOrEqualTo(previousTop));
        expect(line.startCharOffset, greaterThanOrEqualTo(previousOffset));
        expect(line.endCharOffset, greaterThanOrEqualTo(line.startCharOffset));
        previousTop = line.top;
        previousOffset = line.startCharOffset;
      }

      final middle = layout.pageForCharOffset(content.displayText.length ~/ 2);
      expect(middle.pageIndex, inInclusiveRange(0, layout.pages.length - 1));
    });

    test('keeps an empty chapter renderable with a fallback page', () async {
      final content = ReaderV2Content.fromRaw(
        chapterIndex: 2,
        title: '',
        rawText: '',
      );
      final layout = await ReaderV2LayoutEngine().layout(content, spec());

      expect(layout.lines, isEmpty);
      expect(layout.pages, hasLength(1));
      expect(layout.pages.single.chapterIndex, 2);
      expect(layout.pages.single.isChapterStart, isTrue);
      expect(layout.pages.single.isChapterEnd, isTrue);
    });

    test(
      'layout signature changes when presentation-critical style changes',
      () {
        final small = spec(fontSize: 18);
        final large = spec(fontSize: 22);

        expect(small.layoutSignature, isNot(large.layoutSignature));
        expect(small.contentWidth, large.contentWidth);
        expect(small.contentHeight, large.contentHeight);
        expect(small.layoutSignature, isA<int>());
        expect(
          spec(letterSpacing: 1).layoutSignature,
          isNot(small.layoutSignature),
        );
      },
    );

    test('publishes fitting stats for profile validation', () async {
      final observed = <ReaderV2LayoutEngineStats>[];
      ReaderV2LayoutEngine.debugLastStats = null;
      ReaderV2LayoutEngine.debugOnStats = observed.add;
      addTearDown(() => ReaderV2LayoutEngine.debugOnStats = null);

      final content = ReaderV2Content.fromRaw(
        chapterIndex: 4,
        title: '統計測試',
        rawText: List<String>.filled(
          6,
          '這是一段用來觸發排版統計的長文字，包含中文、punctuation，以及 emoji 😀 測試。',
        ).join('\n\n'),
      );
      final layout = await ReaderV2LayoutEngine().layout(content, spec());
      final stats = ReaderV2LayoutEngine.debugLastStats;

      expect(observed, hasLength(1));
      expect(stats, isNotNull);
      expect(stats!.chapterIndex, 4);
      expect(stats.lineCount, layout.lines.length);
      expect(stats.pageCount, layout.pages.length);
      expect(stats.lineLayoutPasses, greaterThan(0));
      expect(stats.widthMeasurePasses, greaterThan(0));
      expect(stats.fittingFallbacks, greaterThanOrEqualTo(0));
      expect(stats.fittingBinarySearchPasses, greaterThanOrEqualTo(0));
    });
  });

  group('ReaderV2LayoutEngine.layoutStep', () {
    ReaderV2Content longContent({int chapterIndex = 0}) {
      return ReaderV2Content.fromRaw(
        chapterIndex: chapterIndex,
        title: '第一章 測試',
        rawText: List<String>.filled(
          40,
          '這是一段用來測試漸進式排版的中文內容，包含標點符號與足夠長度以便跨越多個頁面。',
        ).join('\n\n'),
      );
    }

    test('returns early once minNewExtentPx is satisfied', () async {
      final content = longContent();
      final engine = ReaderV2LayoutEngine();
      final full = await engine.layout(content, spec());

      final step = await engine.layoutStep(
        content: content,
        spec: spec(),
        minNewExtentPx: 40,
      );

      expect(step.cursor.isComplete, isFalse);
      expect(step.layout.isComplete, isFalse);
      expect(step.layout.lines.length, lessThan(full.lines.length));
      expect(step.layout.pages.length, lessThan(full.pages.length));
      // 部分結果的尾頁不能被誤標成章節結尾。
      expect(step.layout.pages.last.isChapterEnd, isFalse);
    });

    test('resuming from a cursor reaches the same result as layout()', () async {
      final content = longContent(chapterIndex: 7);
      final engine = ReaderV2LayoutEngine();
      final full = await engine.layout(content, spec());

      var lines = const <ReaderV2TextLine>[];
      ReaderV2LayoutCursor? cursor;
      var stepCount = 0;
      while (cursor == null || !cursor.isComplete) {
        final step = await engine.layoutStep(
          content: content,
          spec: spec(),
          linesSoFar: lines,
          cursor: cursor,
          minNewExtentPx: 60,
        );
        lines = step.layout.lines;
        cursor = step.cursor;
        stepCount += 1;
        expect(stepCount, lessThan(1000), reason: '避免游標邏輯有誤導致無限迴圈');
      }

      expect(cursor.isComplete, isTrue);
      expect(lines.length, full.lines.length);
      for (var index = 0; index < full.lines.length; index++) {
        expect(lines[index].text, full.lines[index].text);
        expect(lines[index].startCharOffset, full.lines[index].startCharOffset);
        expect(lines[index].endCharOffset, full.lines[index].endCharOffset);
        expect(lines[index].top, full.lines[index].top);
        expect(lines[index].bottom, full.lines[index].bottom);
      }

      // 字元 offset 在續跑邊界上下依然單調不減、無縫接續。
      var previousEnd = -1;
      for (final line in lines) {
        expect(line.startCharOffset, greaterThanOrEqualTo(previousEnd - 1));
        previousEnd = line.endCharOffset;
      }

      expect(stepCount, greaterThan(1), reason: '這個測試要驗證的就是多次續跑');
    });

    test(
      'a step that reaches the end of content marks isComplete and final page as chapter end',
      () async {
        final content = longContent(chapterIndex: 9);
        final engine = ReaderV2LayoutEngine();
        final result = await engine.layoutStep(
          content: content,
          spec: spec(),
          minNewExtentPx: double.infinity,
        );

        expect(result.cursor.isComplete, isTrue);
        expect(result.layout.isComplete, isTrue);
        expect(result.layout.pages.last.isChapterEnd, isTrue);
      },
    );

    test('stepping again after completion is a stable no-op', () async {
      final content = longContent(chapterIndex: 11);
      final engine = ReaderV2LayoutEngine();
      final first = await engine.layoutStep(
        content: content,
        spec: spec(),
        minNewExtentPx: double.infinity,
      );
      final second = await engine.layoutStep(
        content: content,
        spec: spec(),
        linesSoFar: first.layout.lines,
        cursor: first.cursor,
        minNewExtentPx: double.infinity,
      );

      expect(second.cursor.isComplete, isTrue);
      expect(second.layout.lines.length, first.layout.lines.length);
      expect(second.layout.pages.length, first.layout.pages.length);
    });

    test('empty chapter completes immediately with a chapter-end fallback page', () async {
      final content = ReaderV2Content.fromRaw(
        chapterIndex: 3,
        title: '',
        rawText: '',
      );
      final result = await ReaderV2LayoutEngine().layoutStep(
        content: content,
        spec: spec(),
        minNewExtentPx: 100,
      );

      expect(result.cursor.isComplete, isTrue);
      expect(result.layout.isComplete, isTrue);
      expect(result.layout.pages.single.isChapterEnd, isTrue);
    });
  });
}
