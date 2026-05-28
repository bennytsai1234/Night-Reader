import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/content/reader_v2_content.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_engine.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_typography.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ReaderV2LayoutSpec spec({
    Size viewport = const Size(220, 180),
    double fontSize = 18,
  }) {
    return ReaderV2LayoutSpec.fromViewport(
      viewportSize: viewport,
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

  group('ReaderV2LayoutEngine', () {
    test('cuts text into monotonic lines and paginates long chapters', () {
      final content = ReaderV2Content.fromRaw(
        chapterIndex: 0,
        title: '第一章 測試',
        rawText: List<String>.filled(
          18,
          '這是一段用來測試排版切行與分頁的中文內容，包含標點符號與足夠長度。',
        ).join('\n\n'),
      );
      final layout = ReaderV2LayoutEngine().layout(content, spec());

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

    test('keeps an empty chapter renderable with a fallback page', () {
      final content = ReaderV2Content.fromRaw(
        chapterIndex: 2,
        title: '',
        rawText: '',
      );
      final layout = ReaderV2LayoutEngine().layout(content, spec());

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
        expect(
          small.layoutSignature,
          contains(kReaderV2CjkTypographyFeatureSignature),
        );
      },
    );

    test('publishes fitting stats for profile validation', () {
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
      final layout = ReaderV2LayoutEngine().layout(content, spec());
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
}
