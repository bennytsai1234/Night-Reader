import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/reader_v2/hybrid/measure/measurement_store.dart';
import 'package:night_reader/features/reader_v2/hybrid/paragraph/paragraph_cache.dart';
import 'package:night_reader/features/reader_v2/hybrid/pump/layout_pump.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const fontSize = 20.0;
  const contentWidth = 126.0;
  const trailingSpacing = 5.0;
  const textStyle = HybridBlockTextStyle(
    fontSize: fontSize,
    lineHeight: 1.5,
    letterSpacing: 0,
    textAlign: ui.TextAlign.start,
  );

  StyleFingerprint fingerprint() => const StyleFingerprint(
    viewportWidth: 360,
    viewportHeight: 720,
    contentWidth: contentWidth,
    contentHeight: 688,
    fontSize: fontSize,
    lineHeight: 1.5,
    letterSpacing: 0,
    paragraphSpacing: 1,
    paddingTop: 16,
    paddingBottom: 16,
    paddingLeft: 16,
    paddingRight: 16,
    textIndent: 0,
    bold: false,
    justify: false,
    textScaleFactor: 1,
    fontFamilySignature: 'system',
    platformFontSignature: 'test',
  );

  const paragraph =
      '夜讀好書真愉快今晚月色真美麗啊。'
      '第二段文字其實仍然是同一個邏輯段落，這裡故意拉得很長。'
      '第三段內容繼續延伸，讓排版交易一定需要拆成好幾個視覺區段。'
      '最後再補一些字，確保不是只切出兩塊就結束。';

  ChapterBlocks roughBlocks() {
    const cuts = <int>[20, 40, 60, 80];
    final offsets = <int>[0, ...cuts, paragraph.length];
    return ChapterBlocks(
      chapterIndex: 0,
      title: '',
      displayText: paragraph,
      contentHash: 'fixture',
      blocks: [
        for (var i = 0; i < offsets.length - 1; i += 1)
          ChapterBlock(
            key: BlockKey(chapterIndex: 0, blockIndex: i),
            text: paragraph.substring(offsets[i], offsets[i + 1]),
            charRange: HybridTextRange(offsets[i], offsets[i + 1]),
            sourceParagraphIndex: 0,
            isContinuation: i > 0,
          ),
      ],
    );
  }

  LayoutPump makePump(MeasurementStore store, ParagraphCache cache) {
    final fp = fingerprint();
    return LayoutPump(
      paragraphCache: cache,
      measurementStore: store,
      namespace: MeasurementNamespace(
        epoch: LayoutEpoch.initial,
        fingerprint: fp,
      ),
    );
  }

  testWidgets(
    '長邏輯段落只在真實 visual line boundary 拆 transaction，總幾何仍等同未切段',
    (tester) async {
      final alignStore = MeasurementStore();
      final alignCache = ParagraphCache();
      final alignPump = makePump(alignStore, alignCache);

      ChapterBlocks? aligned;
      Object? alignmentError;
      var alignmentDone = false;
      alignPump
          .alignChapterBlocksToVisualLines(
            roughBlocks(),
            maxBlockChars: 30,
            bodyStyle: textStyle,
            contentWidth: contentWidth,
            cellWidth: null,
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
      final segmented = aligned!;
      final groups = segmented.paragraphGroups();
      expect(groups.length, greaterThan(1));
      expect(
        groups.skip(1).every((group) => group.first.layoutBreakBefore),
        isTrue,
      );
      expect(
        segmented.blocks.map((block) => block.text).join(),
        paragraph,
        reason: 'scheduling segmentation must never change chapter text',
      );

      final referenceStore = MeasurementStore();
      final referenceCache = ParagraphCache();
      final referencePump = makePump(referenceStore, referenceCache);
      final fp = fingerprint();
      final referenceBlock = ChapterBlock(
        key: const BlockKey(chapterIndex: 0, blockIndex: 0),
        text: paragraph,
        charRange: HybridTextRange(0, paragraph.length),
        sourceParagraphIndex: 0,
      );
      referencePump.submit(
        LayoutTask(
          block: referenceBlock,
          epoch: LayoutEpoch.initial,
          fingerprint: fp,
          textStyle: textStyle,
          contentWidth: contentWidth,
          trailingSpacing: trailingSpacing,
        ),
      );
      while (referencePump.queueDepth > 0) {
        final completed = await referencePump.pumpPending();
        if (completed == 0) await tester.pump();
      }
      final referenceParagraph = referenceCache
          .acquireEntry(referenceBlock.key, LayoutEpoch.initial)!
          .paragraph;
      final lineBoundaries = <int>{};
      var lineOffset = 0;
      while (lineOffset < paragraph.length) {
        final range = referenceParagraph.getLineBoundary(
          ui.TextPosition(offset: lineOffset),
        );
        if (!range.isValid || range.end <= lineOffset) break;
        lineBoundaries.add(range.end);
        lineOffset = range.end;
      }
      for (final group in groups.skip(1)) {
        expect(
          lineBoundaries,
          contains(group.first.charRange.start),
          reason: 'every independent transaction must start at a real line boundary',
        );
      }

      final segmentedStore = MeasurementStore();
      final segmentedCache = ParagraphCache();
      final segmentedPump = makePump(segmentedStore, segmentedCache);
      for (final group in groups) {
        final last = group.last;
        final nextIndex = last.blockIndex + 1;
        final next = nextIndex < segmented.blocks.length
            ? segmented.blocks[nextIndex]
            : null;
        final lookahead =
            next != null &&
                next.isContinuation &&
                next.layoutBreakBefore &&
                next.sourceParagraphIndex == last.sourceParagraphIndex &&
                next.text.isNotEmpty
            ? String.fromCharCode(next.text.runes.first)
            : '';
        segmentedPump.submit(
          LayoutTask(
            block: group.first,
            continuationBlocks: group.skip(1).toList(growable: false),
            epoch: LayoutEpoch.initial,
            fingerprint: fp,
            textStyle: textStyle,
            contentWidth: contentWidth,
            trailingSpacing: next == null ? trailingSpacing : 0,
            trailingLayoutLookahead: lookahead,
          ),
        );
      }
      while (segmentedPump.queueDepth > 0) {
        final completed = await segmentedPump.pumpPending();
        if (completed == 0) await tester.pump();
      }

      final namespace = MeasurementNamespace(
        epoch: LayoutEpoch.initial,
        fingerprint: fp,
      );
      var totalHeight = 0.0;
      var totalLines = 0;
      for (final block in segmented.blocks) {
        final metrics = segmentedStore.get(namespace, block.key)!;
        totalHeight += metrics.height;
        totalLines += metrics.lineCount;
      }
      expect(
        totalHeight,
        closeTo(referenceParagraph.height + trailingSpacing, 0.01),
      );
      expect(totalLines, referenceParagraph.numberOfLines);

      alignPump.dispose();
      referencePump.dispose();
      segmentedPump.dispose();
      alignCache.dispose();
      referenceCache.dispose();
      segmentedCache.dispose();
    },
  );
}
