import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader/text_view/core/text_view_types.dart';
import 'package:night_reader/features/reader/text_view/layout/visual_line_layout_engine.dart';
import 'package:night_reader/features/reader/text_view/layout/reader_paragraph_layout.dart';
import 'package:night_reader/features/reader/layout/reader_layout_spec.dart';

void main() {
  // 18 號字的字格約 18 寬，這個內容寬湊整數個字格後還剩大半格。
  const contentWidth = 390.0;
  const layout = ReaderParagraphLayout();

  double cellAt(double letterSpacing) => layout.measureCellWidth(
    fontSize: 18,
    letterSpacing: letterSpacing,
    bold: false,
  )!;

  test('without justification the leftover space insets both edges', () {
    final frame = ReaderTextLayoutFrame.centered(
      contentWidth: contentWidth,
      cellWidth: cellAt(0),
    );

    expect(frame.leftInset, greaterThan(1));
    expect(frame.rightInset, greaterThan(1));
  });

  test('justified letter spacing fills the content width with the same '
      'number of cells', () {
    final cell = cellAt(0);
    final cells = (contentWidth / cell).floor();
    final spacing = ReaderTextLayoutFrame.justifiedLetterSpacing(
      contentWidth: contentWidth,
      cellWidth: cell,
      letterSpacing: 0,
    );
    final justifiedCell = cellAt(spacing);
    final frame = ReaderTextLayoutFrame.centered(
      contentWidth: contentWidth,
      cellWidth: justifiedCell,
    );

    expect(spacing, greaterThan(0));
    expect(spacing, lessThan(cell / cells));
    expect((frame.width / justifiedCell).floor(), cells);
    expect(frame.leftInset, lessThan(0.05));
    expect(frame.rightInset, lessThan(0.05));
  });

  test('justification keeps the user letter spacing as its base', () {
    final spacing = ReaderTextLayoutFrame.justifiedLetterSpacing(
      contentWidth: contentWidth,
      cellWidth: cellAt(1),
      letterSpacing: 1,
    );

    expect(spacing, greaterThan(1));
  });

  group('line chars', () {
    const cell = 19.0;
    double padding(double viewport, int chars) =>
        ReaderTextLayoutFrame.sidePadding(
          viewportWidth: viewport,
          minPadding: 12,
          cellWidth: cell,
          lineChars: chars,
        );

    test('a phone that holds fewer chars keeps the minimum margin', () {
      // 393 寬扣兩側 12 放得下 19 字，比 32 少：撐滿，跟沒有字數上限一樣。
      expect(
        ReaderTextLayoutFrame.lineCapacity(
          viewportWidth: 393,
          minPadding: 12,
          cellWidth: cell,
        ),
        19,
      );
      expect(padding(393, 32), 12);
      expect(padding(393, 19), 12);
    });

    test('a wide screen centres a column of exactly that many chars', () {
      for (final viewport in [1280.0, 880.0]) {
        final side = padding(viewport, 32);
        final content = viewport - side * 2;
        final frame = ReaderTextLayoutFrame.centered(
          contentWidth: content,
          cellWidth: cell,
        );
        expect((frame.width / cell).floor(), 32);
        // 欄寬剛好是整數格：左右對齊沒有零頭可攤，字距照使用者設的。
        expect(
          ReaderTextLayoutFrame.justifiedLetterSpacing(
            contentWidth: content,
            cellWidth: cell,
            letterSpacing: 1,
          ),
          closeTo(1, 1e-9),
        );
      }
    });

    test('fewer chars on a phone widen both margins evenly', () {
      final side = padding(393, 17);
      expect(side, greaterThan(12));
      expect(393 - side * 2, closeTo(17 * cell, 0.1));
    });
  });

  test('a content box narrower than one cell keeps the letter spacing', () {
    expect(
      ReaderTextLayoutFrame.justifiedLetterSpacing(
        contentWidth: 10,
        cellWidth: 18,
        letterSpacing: 0,
      ),
      0,
    );
  });

  // 每行字數最少 1、首行縮排最多 4，兩個各自合法的設定湊在一起時，縮排比一行
  // 還寬就排不出來（開書停在骨架），一樣寬時第一行的字超出邊界。
  group('首行縮排放不下一行時', () {
    const cell = 20.0;
    for (final (lineChars, indent, expected) in [
      (1, 2, 0),
      (1, 1, 0),
      (2, 2, 1),
      (3, 4, 2),
      (3, 2, 2),
      (60, 2, 2),
    ]) {
      test('每行 $lineChars 字、縮排 $indent 字：縮排 $expected 字，第一行放得下字', () {
        final width = lineChars * cell + 0.05;
        final spec = ReaderLayoutSpec.fromViewport(
          viewportSize: Size(width + 24, 800),
          cellWidth: cell,
          style: ReaderLayoutStyle(
            fontSize: cell,
            lineHeight: 1.5,
            letterSpacing: 0,
            paragraphSpacing: 0,
            chapterSpacing: 0,
            paddingTop: 0,
            paddingBottom: 0,
            paddingLeft: 12,
            paddingRight: 12,
            textIndent: indent,
          ),
        );
        expect(spec.style.textIndent, expected);
        final plan = const VisualLineLayoutEngine().planBlock(
          text: '天色漸暗城門即將關閉',
          start: 0,
          maxBlockChars: 10000,
          textStyle: const BlockTextStyle(
            fontSize: cell,
            lineHeight: 1.5,
            letterSpacing: 0,
          ),
          contentWidth: spec.textLayoutFrame.width,
          cellWidth: cell,
          indentChars: spec.style.textIndent,
        );
        final firstLine = plan.visualLineBreakOffsets.isEmpty
            ? 10
            : plan.visualLineBreakOffsets.first;
        expect(
          spec.style.textIndent + firstLine,
          lessThanOrEqualTo(lineChars),
          reason: '縮排加上第一行的字不超出一行',
        );
      });
    }
  });
}
