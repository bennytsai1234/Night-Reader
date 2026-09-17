import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/features/tts/reader_v2_tts_highlight.dart';
import 'package:night_reader/features/reader_v2/hybrid/anchor/anchor_manager.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_contracts.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/reader_v2/hybrid/overlay/tts_highlight_overlay.dart';
import 'package:night_reader/features/reader_v2/hybrid/progress/hybrid_progress.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_style.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';

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

    test('uses semantic chapter length instead of admitted geometry', () {
      const progress = HybridProgress(chapterCount: 3);

      final quarter = progress.progressForLocation(
        const ReaderV2Location(chapterIndex: 0, charOffset: 50),
        chapterLength: 200,
      );
      expect(quarter.chapterPercent, 25);
      expect(quarter.chapterLabel, '第 1/3 章 · 本章 2/10');
      expect(quarter.percentLabel, '全書 8.3%');

      final end = progress.progressForLocation(
        const ReaderV2Location(chapterIndex: 0, charOffset: 200),
        chapterLength: 200,
      );
      expect(end.chapterPercent, 100);
      expect(end.chapterLabel, '第 1/3 章 · 本章 10/10');
      expect(end.percentLabel, '全書 33.3%');

      final next = progress.progressForLocation(
        const ReaderV2Location(chapterIndex: 1, charOffset: 0),
        chapterLength: 500,
      );
      expect(next.chapterPercent, 0);
      expect(next.chapterLabel, '第 2/3 章 · 本章 0/10');
      expect(next.percentLabel, '全書 33.3%');
    });

    test('progress snapshots with the same displayed values compare equal', () {
      const first = HybridProgressSnapshot(
        chapterIndex: 2,
        chapterCount: 10,
        chapterPercent: 35.01,
      );
      const second = HybridProgressSnapshot(
        chapterIndex: 2,
        chapterCount: 10,
        chapterPercent: 35.04,
      );
      const changed = HybridProgressSnapshot(
        chapterIndex: 2,
        chapterCount: 10,
        chapterPercent: 35.6,
      );

      expect(first.chapterLabel, '第 3/10 章 · 本章 3/10');
      expect(second.chapterLabel, '第 3/10 章 · 本章 3/10');
      expect(changed.chapterLabel, '第 3/10 章 · 本章 3/10');
      expect(first.percentLabel, '全書 23.5%');
      expect(second.percentLabel, '全書 23.5%');
      expect(changed.percentLabel, '全書 23.6%');
      expect(first, second);
      expect(first, isNot(changed));
    });
  });
}
