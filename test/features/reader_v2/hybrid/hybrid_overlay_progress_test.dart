import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/features/tts/reader_v2_tts_highlight.dart';
import 'package:night_reader/features/reader_v2/hybrid/anchor/anchor_manager.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/reader_v2/hybrid/measure/document_index.dart';
import 'package:night_reader/features/reader_v2/hybrid/overlay/tts_highlight_overlay.dart';
import 'package:night_reader/features/reader_v2/hybrid/progress/hybrid_progress.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_style.dart';

void main() {
  group('Hybrid overlay/progress helpers', () {
    test('uses existing anchor offset clamp', () {
      expect(AnchorManager.anchorOffsetInViewport(80), 24);
      expect(AnchorManager.anchorOffsetInViewport(400), 80);
      expect(AnchorManager.anchorOffsetInViewport(1000), 120);
    });

    test('computes TTS full-line highlight rects', () {
      final rects = HybridTtsHighlightPainter.rectsFor(
        lines: const <HybridLineBox>[
          HybridLineBox(
            key: BlockKey(chapterIndex: 0, blockIndex: 0),
            top: 10,
            bottom: 30,
            charRange: HybridTextRange(5, 10),
          ),
        ],
        style: const ReaderV2Style(
          fontSize: 18,
          lineHeight: 1.5,
          letterSpacing: 0,
          paragraphSpacing: 1,
          paddingTop: 12,
          paddingBottom: 12,
          paddingLeft: 16,
          paddingRight: 20,
        ),
        size: const Size(200, 100),
        highlight: const ReaderV2TtsHighlight(
          chapterIndex: 0,
          highlightStart: 6,
          highlightEnd: 7,
        ),
      );

      expect(rects, hasLength(1));
      expect(rects.single.left, 10);
      expect(rects.single.right, 186);
      expect(rects.single.top, 21);
      expect(rects.single.bottom, 43);
    });

    test('caps non-terminal chapter percent at 99.9', () {
      final index = DocumentIndex(
        centerKey: const BlockKey(chapterIndex: 0, blockIndex: 0),
      )..admitAll({
        const BlockKey(chapterIndex: 0, blockIndex: 0): const BlockMetrics(
          height: 100,
          lineCount: 1,
        ),
        const BlockKey(chapterIndex: 1, blockIndex: 0): const BlockMetrics(
          height: 100,
          lineCount: 1,
        ),
      });

      final progress = HybridProgress(documentIndex: index, chapterCount: 3);
      expect(progress.progressForOffset(100).chapterPercent, 0);
      expect(progress.progressForOffset(99.9).chapterPercent, 99.9);
    });
  });
}
