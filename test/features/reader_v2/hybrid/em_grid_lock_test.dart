import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/reader_v2/hybrid/measure/measurement_store.dart';
import 'package:night_reader/features/reader_v2/hybrid/paragraph/paragraph_cache.dart';
import 'package:night_reader/features/reader_v2/hybrid/pump/layout_pump.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';

// em-grid 鎖寬（2026-07-19）：contentWidth 修剪到實測 cell 整數倍讓每列
// 殘差歸零 + 內文 start 對齊，直行格線不再逐列漂移。
// 測試字型（FlutterTest）所有字形 advance = fontSize，cell ≈ fontSize。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('measureCellWidth', () {
    test('回傳正的全形 advance 且可重複取得', () {
      final cell = LayoutPump.measureCellWidth(
        fontSize: 20,
        letterSpacing: 0,
        bold: false,
      );
      expect(cell, isNotNull);
      expect(cell!, closeTo(20.0, 0.5), reason: '測試字型 advance = fontSize');
      final again = LayoutPump.measureCellWidth(
        fontSize: 20,
        letterSpacing: 0,
        bold: false,
      );
      expect(again, cell, reason: '同樣式必須命中快取回同值');
    });

    test('letterSpacing 計入 advance', () {
      final cell = LayoutPump.measureCellWidth(
        fontSize: 20,
        letterSpacing: 2,
        bold: false,
      );
      expect(cell, isNotNull);
      expect(cell!, closeTo(22.0, 0.5));
    });

    test('非法輸入回 null（呼叫端退回不鎖寬）', () {
      expect(
        LayoutPump.measureCellWidth(
          fontSize: 0,
          letterSpacing: 0,
          bold: false,
        ),
        isNull,
      );
      expect(
        LayoutPump.measureCellWidth(
          fontSize: double.nan,
          letterSpacing: 0,
          bold: false,
        ),
        isNull,
      );
    });
  });

  group('ReaderV2LayoutSpec.fromViewport 鎖寬', () {
    const style = ReaderV2LayoutStyle(
      fontSize: 20,
      lineHeight: 1.5,
      letterSpacing: 0,
      paragraphSpacing: 1,
      paddingTop: 8,
      paddingBottom: 8,
      paddingLeft: 16,
      paddingRight: 16,
    );

    test('contentWidth 修剪為 cell 整數倍、殘差平分回左右 padding', () {
      final spec = ReaderV2LayoutSpec.fromViewport(
        viewportSize: const ui.Size(413, 800),
        style: style,
        cellWidth: 20,
      );
      // raw = 413 - 32 = 381 → 19 格；slack 0.05。
      expect(spec.cellWidth, 20);
      expect(spec.contentWidth, closeTo(19 * 20 + 0.05, 0.001));
      final residual = 381 - spec.contentWidth;
      expect(spec.style.paddingLeft, closeTo(16 + residual / 2, 0.001));
      expect(spec.style.paddingRight, closeTo(16 + residual / 2, 0.001));
      // 版面帳要平：padding + contentWidth = viewport 寬。
      expect(
        spec.style.paddingLeft + spec.contentWidth + spec.style.paddingRight,
        closeTo(413, 0.001),
      );
    });

    test('未給 cell 或 viewport 塞不下一格時維持原始 contentWidth', () {
      final unlocked = ReaderV2LayoutSpec.fromViewport(
        viewportSize: const ui.Size(413, 800),
        style: style,
      );
      expect(unlocked.cellWidth, isNull);
      expect(unlocked.contentWidth, 381);
      expect(unlocked.style.paddingLeft, 16);

      final tooNarrow = ReaderV2LayoutSpec.fromViewport(
        viewportSize: const ui.Size(30, 800),
        style: style,
        cellWidth: 20,
      );
      expect(tooNarrow.cellWidth, isNull);
      expect(tooNarrow.contentWidth, 1.0);
    });
  });

  group('鎖寬 + start 對齊的直行格線', () {
    const fontSize = 20.0;

    test('純 CJK 多列：逐字落在 k×cell 格點、跨列同相位、滿列切齊右緣', () async {
      final cell = LayoutPump.measureCellWidth(
        fontSize: fontSize,
        letterSpacing: 0,
        bold: false,
      )!;
      final contentWidth = 12 * cell + 0.05;
      // 縮排 2 + 30 字 = 32 格 → 12 / 12 / 8 三列。
      final (paragraph, cleanup) = await _layoutTask(
        _task(
          text: '夜' * 30,
          contentWidth: contentWidth,
          indentChars: 2,
          cellWidth: cell,
        ),
      );
      final lines = paragraph.computeLineMetrics();
      expect(lines.length, 3);
      // 滿列自然切齊右緣（誤差僅 slack），不靠 justify。
      expect(lines[0].width, closeTo(12 * cell, 0.1));
      expect(lines[1].width, closeTo(12 * cell, 0.1));
      // 縮排 placeholder 佔恰好 2 格。
      final placeholders = paragraph.getBoxesForPlaceholders();
      expect(placeholders.length, 2);
      expect(placeholders[1].right, closeTo(2 * cell, 0.1));
      // 逐字驗 k×cell 格點：首列 offset 2..11、次列 12..23、末列 24..31，
      // 跨列同一組格點（同相位）才是「直行對齊」。
      for (var offset = 2; offset < 32; offset += 1) {
        final box = paragraph.getBoxesForRange(offset, offset + 1).single;
        final k = (box.left / cell).round();
        expect(
          box.left,
          closeTo(k * cell, 0.1),
          reason: 'offset $offset 落格 (left=${box.left})',
        );
      }
      cleanup();
    });

    test('避頭尾推字列：右緣缺口 ≤ 1 cell，次列仍在格點上', () async {
      final cell = LayoutPump.measureCellWidth(
        fontSize: fontSize,
        letterSpacing: 0,
        bold: false,
      )!;
      final contentWidth = 12 * cell + 0.05;
      // 第 13 字是全形逗號：自然斷行會讓它成為次列行首，避頭尾把第 12 個
      // 「夜」推下去 → 首列 11 字、右緣留恰好一格空。
      final (paragraph, cleanup) = await _layoutTask(
        _task(
          text: '${'夜' * 12}，${'夜' * 5}',
          contentWidth: contentWidth,
          cellWidth: cell,
        ),
      );
      final lines = paragraph.computeLineMetrics();
      expect(lines.length, 2);
      final gap = contentWidth - lines[0].width;
      expect(gap, greaterThan(0.5 * cell));
      expect(gap, lessThanOrEqualTo(cell + 0.1), reason: '右緣缺口不得超過一格');
      // start 對齊不得把缺口攤進字距：次列每字仍在 k×cell 格點。
      // 首列 11 字（offset 0..10），次列自 offset 11 起。
      final line2 = paragraph.getLineBoundary(
        const ui.TextPosition(offset: 11),
      );
      for (var offset = line2.start; offset < line2.end; offset += 1) {
        final box = paragraph.getBoxesForRange(offset, offset + 1).single;
        final k = (box.left / cell).round();
        expect(box.left, closeTo(k * cell, 0.1));
      }
      cleanup();
    });

    test('含拉丁 run 的列不 crash，行前 CJK 仍在格點', () async {
      final cell = LayoutPump.measureCellWidth(
        fontSize: fontSize,
        letterSpacing: 0,
        bold: false,
      )!;
      final contentWidth = 12 * cell + 0.05;
      final (paragraph, cleanup) = await _layoutTask(
        _task(
          text: '${'夜' * 5}abc${'夜' * 20}',
          contentWidth: contentWidth,
          cellWidth: cell,
        ),
      );
      expect(paragraph.computeLineMetrics().length, greaterThan(1));
      for (var offset = 0; offset < 5; offset += 1) {
        final box = paragraph.getBoxesForRange(offset, offset + 1).single;
        final k = (box.left / cell).round();
        expect(box.left, closeTo(k * cell, 0.1));
      }
      cleanup();
    });

    test('placeholder 寬取 task.cellWidth 而非 fontSize', () async {
      // 刻意給與 fontSize 不同的 cell，證明 placeholder 是 cell 寬。
      const syntheticCell = 23.0;
      final (paragraph, cleanup) = await _layoutTask(
        _task(
          text: '夜' * 4,
          contentWidth: 12 * syntheticCell,
          indentChars: 2,
          cellWidth: syntheticCell,
        ),
      );
      final placeholders = paragraph.getBoxesForPlaceholders();
      expect(placeholders.length, 2);
      expect(placeholders[0].right, closeTo(syntheticCell, 0.01));
      expect(placeholders[1].right, closeTo(2 * syntheticCell, 0.01));
      final firstGlyph = paragraph.getBoxesForRange(2, 3).single;
      expect(firstGlyph.left, closeTo(2 * syntheticCell, 0.01));
      cleanup();
    });
  });
}

LayoutTask _task({
  required String text,
  required double contentWidth,
  int indentChars = 0,
  double? cellWidth,
}) {
  final fingerprint = _fingerprint(contentWidth: contentWidth);
  return LayoutTask(
    block: ChapterBlock(
      key: const BlockKey(chapterIndex: 0, blockIndex: 0),
      text: text,
      charRange: HybridTextRange(0, text.length),
      sourceParagraphIndex: 0,
    ),
    epoch: LayoutEpoch.initial,
    fingerprint: fingerprint,
    textStyle: const HybridBlockTextStyle(
      fontSize: 20,
      lineHeight: 1.5,
      letterSpacing: 0,
      textAlign: ui.TextAlign.start,
    ),
    contentWidth: contentWidth,
    indentChars: indentChars,
    cellWidth: cellWidth,
  );
}

Future<(ui.Paragraph, void Function())> _layoutTask(LayoutTask task) async {
  final store = MeasurementStore();
  final cache = ParagraphCache();
  final pump = LayoutPump(
    paragraphCache: cache,
    measurementStore: store,
    namespace: MeasurementNamespace(
      epoch: LayoutEpoch.initial,
      fingerprint: task.fingerprint,
    ),
  );
  pump.submit(task);
  expect(await pump.pumpPending(), 1);
  final paragraph = cache.acquire(task.key, LayoutEpoch.initial)!;
  return (
    paragraph,
    () {
      pump.dispose();
      cache.dispose();
    },
  );
}

StyleFingerprint _fingerprint({required double contentWidth}) {
  return StyleFingerprint(
    viewportWidth: 320,
    viewportHeight: 640,
    contentWidth: contentWidth,
    contentHeight: 600,
    fontSize: 20,
    lineHeight: 1.5,
    letterSpacing: 0,
    paragraphSpacing: 1,
    paddingTop: 8,
    paddingBottom: 8,
    paddingLeft: 16,
    paddingRight: 16,
    textIndent: 2,
    bold: false,
    justify: false,
    textScaleFactor: 1,
    fontFamilySignature: 'system',
    platformFontSignature: 'test',
  );
}
