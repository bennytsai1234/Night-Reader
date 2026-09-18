import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/reader_v2/hybrid/measure/measurement_store.dart';
import 'package:night_reader/features/reader_v2/hybrid/paragraph/paragraph_cache.dart';
import 'package:night_reader/features/reader_v2/hybrid/pump/layout_cost_model.dart';
import 'package:night_reader/features/reader_v2/hybrid/pump/layout_pump.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  StyleFingerprint fingerprint({
    required bool compensate,
    required double contentWidth,
  }) => StyleFingerprint(
    viewportWidth: 360,
    viewportHeight: 720,
    contentWidth: contentWidth,
    contentHeight: 688,
    fontSize: 20,
    lineHeight: 1.5,
    letterSpacing: 0,
    paragraphSpacing: 1,
    paddingTop: 16,
    paddingBottom: 16,
    paddingLeft: 16,
    paddingRight: 16,
    textIndent: 0,
    bold: false,
    justify: true,
    textScaleFactor: 1,
    fontFamilySignature: 'system',
    platformFontSignature: 'test',
    lastLineSpacingCompensation: compensate,
  );

  testWidgets(
    'visual segmentation keeps semantic last-line compensation on the final continuation transaction',
    (tester) async {
      const fontSize = 20.0;
      final cellWidth = LayoutPump.measureCellWidth(
        fontSize: fontSize,
        letterSpacing: 0,
        bold: false,
      );
      expect(cellWidth, isNotNull);
      final contentWidth = cellWidth! * 6.3;
      final text = List<String>.filled(53, '字').join();
      const style = HybridBlockTextStyle(
        fontSize: fontSize,
        lineHeight: 1.5,
        letterSpacing: 0,
        textAlign: ui.TextAlign.justify,
      );
      final source = ChapterBlocks(
        chapterIndex: 0,
        title: '',
        displayText: text,
        contentHash: 'fixture',
        blocks: <ChapterBlock>[
          ChapterBlock(
            key: const BlockKey(chapterIndex: 0, blockIndex: 0),
            text: text,
            charRange: HybridTextRange(0, text.length),
            sourceParagraphIndex: 0,
          ),
        ],
      );

      final compensatedFingerprint = fingerprint(
        compensate: true,
        contentWidth: contentWidth,
      );
      final compensatedStore = MeasurementStore();
      final compensatedCache = ParagraphCache();
      final compensatedPump = LayoutPump(
        paragraphCache: compensatedCache,
        measurementStore: compensatedStore,
        namespace: MeasurementNamespace(
          epoch: LayoutEpoch.initial,
          fingerprint: compensatedFingerprint,
        ),
      );

      ChapterBlocks? aligned;
      Object? alignmentError;
      var alignmentDone = false;
      compensatedPump
          .alignChapterBlocksToVisualLines(
            source,
            maxBlockChars: 24,
            bodyStyle: style,
            contentWidth: contentWidth,
            cellWidth: cellWidth,
            textIndent: 0,
          )
          .then(
            (value) {
              aligned = value;
              alignmentDone = true;
            },
            onError: (Object error, StackTrace _) {
              alignmentError = error;
              alignmentDone = true;
            },
          );
      for (var i = 0; i < 120 && !alignmentDone; i += 1) {
        await tester.pump();
      }
      expect(alignmentError, isNull);
      expect(alignmentDone, isTrue);

      final groups = aligned!.paragraphGroups();
      expect(groups.length, greaterThan(1));
      final finalGroup = groups.last;
      expect(finalGroup.first.isContinuation, isTrue);
      expect(finalGroup.first.layoutBreakBefore, isTrue);

      final finalTask = LayoutTask(
        block: finalGroup.first,
        continuationBlocks: finalGroup.skip(1).toList(growable: false),
        epoch: LayoutEpoch.initial,
        fingerprint: compensatedFingerprint,
        textStyle: style,
        contentWidth: contentWidth,
        cellWidth: cellWidth,
      );
      expect(
        LayoutCostModel.mayCompensateLastLine(finalTask),
        isTrue,
        reason:
            'isContinuation describes semantic paragraph identity; an empty lookahead means this is the real paragraph end',
      );

      final nextGroup = groups[1];
      final firstTask = LayoutTask(
        block: groups.first.first,
        continuationBlocks: groups.first.skip(1).toList(growable: false),
        epoch: LayoutEpoch.initial,
        fingerprint: compensatedFingerprint,
        textStyle: style,
        contentWidth: contentWidth,
        cellWidth: cellWidth,
        trailingLayoutLookahead: String.fromCharCode(
          nextGroup.first.text.runes.first,
        ),
      );
      expect(
        LayoutCostModel.mayCompensateLastLine(firstTask),
        isFalse,
        reason: 'a lookahead means the semantic paragraph continues',
      );

      compensatedPump.submit(finalTask);
      expect(await compensatedPump.pumpPending(), 1);
      final compensatedParagraph = compensatedCache
          .acquireEntry(finalGroup.first.key, LayoutEpoch.initial)!
          .paragraph;
      expect(compensatedParagraph.numberOfLines, greaterThanOrEqualTo(2));

      final baselineFingerprint = fingerprint(
        compensate: false,
        contentWidth: contentWidth,
      );
      final baselineStore = MeasurementStore();
      final baselineCache = ParagraphCache();
      final baselinePump = LayoutPump(
        paragraphCache: baselineCache,
        measurementStore: baselineStore,
        namespace: MeasurementNamespace(
          epoch: LayoutEpoch.initial,
          fingerprint: baselineFingerprint,
        ),
      );
      baselinePump.submit(
        LayoutTask(
          block: finalGroup.first,
          continuationBlocks: finalGroup.skip(1).toList(growable: false),
          epoch: LayoutEpoch.initial,
          fingerprint: baselineFingerprint,
          textStyle: style,
          contentWidth: contentWidth,
          cellWidth: cellWidth,
        ),
      );
      expect(await baselinePump.pumpPending(), 1);
      final baselineParagraph = baselineCache
          .acquireEntry(finalGroup.first.key, LayoutEpoch.initial)!
          .paragraph;

      final compensatedLastWidth = compensatedParagraph.computeLineMetrics().last.width;
      final baselineLastWidth = baselineParagraph.computeLineMetrics().last.width;
      expect(compensatedLastWidth, greaterThan(baselineLastWidth));
      expect(compensatedLastWidth, lessThanOrEqualTo(contentWidth + 0.01));

      compensatedPump.dispose();
      baselinePump.dispose();
      compensatedCache.dispose();
      baselineCache.dispose();
    },
  );
}
