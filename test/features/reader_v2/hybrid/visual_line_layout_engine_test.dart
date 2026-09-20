import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/reader_v2/hybrid/layout/reader_paragraph_layout.dart';
import 'package:night_reader/features/reader_v2/hybrid/layout/visual_line_layout_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const policy = VisualLineBreakPolicy();

  test('CJK native word grouping does not move a fitting grapheme', () {
    const text = '今天晚上我想閱讀小說';
    const overflowing = ShapedGrapheme(
      start: 5,
      end: 6,
      left: 5,
      right: 6,
      wordStart: 4,
      wordEnd: 6,
    );

    final preferred = policy.preferredWordBreak(
      text: text,
      overflowing: overflowing,
      lineStart: 0,
      graphemeStarts: <int>{0, 1, 2, 3, 4, 5, 6, 7, 8, 9},
    );

    expect(preferred, isNull);
  });

  test('Latin native word grouping may keep the next word together', () {
    const text = 'hello world';
    const overflowing = ShapedGrapheme(
      start: 7,
      end: 8,
      left: 7,
      right: 8,
      wordStart: 6,
      wordEnd: 11,
    );

    final preferred = policy.preferredWordBreak(
      text: text,
      overflowing: overflowing,
      lineStart: 0,
      graphemeStarts: <int>{0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10},
    );

    expect(preferred, 6);
  });

  testWidgets('line-boundary whitespace stays with the previous line', (
    _,
  ) async {
    const text = 'aaaaa aaaaa';
    const style = HybridBlockTextStyle(
      fontSize: 20,
      lineHeight: 1.5,
      letterSpacing: 0,
    );
    const paragraphLayout = ReaderParagraphLayout();
    const engine = VisualLineLayoutEngine(paragraphLayout: paragraphLayout);

    final shaped = paragraphLayout.shapeGraphemes(
      text: text,
      textStyle: style,
    );
    final firstWordWidth = shaped[4].right - shaped.first.left;
    final spaceWidth = shaped[5].right - shaped[5].left;
    expect(spaceWidth, greaterThan(0));

    final plan = engine.planBlock(
      text: text,
      start: 0,
      maxBlockChars: text.length,
      textStyle: style,
      contentWidth: firstWordWidth + spaceWidth * 0.25,
      cellWidth: null,
      indentChars: 0,
    );

    expect(
      plan.visualLineBreakOffsets,
      <int>[6],
      reason:
          'separator width must not create an empty visual line between words',
    );
  });
}
