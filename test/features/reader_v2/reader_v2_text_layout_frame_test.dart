import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/hybrid/layout/reader_paragraph_layout.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';

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
    final frame = ReaderV2TextLayoutFrame.centered(
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
    final spacing = ReaderV2TextLayoutFrame.justifiedLetterSpacing(
      contentWidth: contentWidth,
      cellWidth: cell,
      letterSpacing: 0,
    );
    final justifiedCell = cellAt(spacing);
    final frame = ReaderV2TextLayoutFrame.centered(
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
    final spacing = ReaderV2TextLayoutFrame.justifiedLetterSpacing(
      contentWidth: contentWidth,
      cellWidth: cellAt(1),
      letterSpacing: 1,
    );

    expect(spacing, greaterThan(1));
  });

  group('line chars', () {
    const cell = 19.0;
    double padding(double viewport, int chars) =>
        ReaderV2TextLayoutFrame.sidePadding(
          viewportWidth: viewport,
          minPadding: 12,
          cellWidth: cell,
          lineChars: chars,
        );

    test('a phone that holds fewer chars keeps the minimum margin', () {
      // 393 寬扣兩側 12 放得下 19 字，比 32 少：撐滿，跟沒有字數上限一樣。
      expect(
        ReaderV2TextLayoutFrame.lineCapacity(
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
        final frame = ReaderV2TextLayoutFrame.centered(
          contentWidth: content,
          cellWidth: cell,
        );
        expect((frame.width / cell).floor(), 32);
        // 欄寬剛好是整數格：左右對齊沒有零頭可攤，字距照使用者設的。
        expect(
          ReaderV2TextLayoutFrame.justifiedLetterSpacing(
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
      ReaderV2TextLayoutFrame.justifiedLetterSpacing(
        contentWidth: 10,
        cellWidth: 18,
        letterSpacing: 0,
      ),
      0,
    );
  });
}
