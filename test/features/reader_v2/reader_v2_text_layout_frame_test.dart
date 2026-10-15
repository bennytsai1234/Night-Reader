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
