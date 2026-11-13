import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/reader_v2/hybrid/layout/reader_paragraph_layout.dart';
import 'package:night_reader/features/reader_v2/hybrid/layout/visual_line_layout_engine.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';

/// 章節標題的粗細與對齊：只有標題吃這兩個設定，置中只移動畫出來的行，
/// 不改折行。
///
/// 測試字型每個字一樣寬，字級 20 時一格 20px。
const double _cell = 20;
const _engine = VisualLineLayoutEngine();
const _layout = ReaderParagraphLayout();

HybridBlockTextStyle _style({bool center = false}) => HybridBlockTextStyle(
  fontSize: _cell,
  lineHeight: 1.5,
  letterSpacing: 0,
  bold: true,
  center: center,
);

VisualLineBlockPlan _plan(String text, double width, {bool center = false}) =>
    _engine.planBlock(
      text: text,
      start: 0,
      maxBlockChars: 10000,
      textStyle: _style(center: center),
      contentWidth: width,
      cellWidth: _cell,
      indentChars: 0,
    );

ui.Paragraph _draw(String text, double width, {required bool center}) {
  final plan = _plan(text, width, center: center);
  return _layout.build(
    sourceText: text,
    textMap: ParagraphTextMap(
      sourceLength: text.length,
      indentLength: 0,
      visualLineBreakOffsets: plan.visualLineBreakOffsets,
      spacers: plan.spacers,
    ),
    textStyle: _style(center: center),
    contentWidth: width,
    cellWidth: _cell,
    textColor: const ui.Color(0xFF000000),
  );
}

ReaderV2LayoutStyle _layoutStyle({
  bool bold = false,
  bool titleBold = true,
  bool titleCenter = false,
  String? fontFamily,
}) => ReaderV2LayoutStyle(
  fontSize: 18,
  lineHeight: 1.5,
  letterSpacing: 0,
  paragraphSpacing: 0.5,
  paddingTop: 0,
  paddingBottom: 0,
  paddingLeft: 12,
  paddingRight: 12,
  bold: bold,
  titleBold: titleBold,
  titleCenter: titleCenter,
  fontFamily: fontFamily,
);

void main() {
  test('a centered title line sits in the middle of the column', () {
    const width = 200.0;
    final left = _draw('第一章', width, center: false);
    final centered = _draw('第一章', width, center: true);
    expect(left.getBoxesForRange(0, 1).single.left, 0);
    // 三個字 60px，左右各留 70px。
    expect(centered.getBoxesForRange(0, 1).single.left, closeTo(70, 0.01));
    expect(centered.getBoxesForRange(2, 3).single.right, closeTo(130, 0.01));
    left.dispose();
    centered.dispose();
  });

  test('centering does not change where a long title wraps', () {
    const text = '第一百二十三章 一個很長很長的章節名稱';
    const width = 200.0;
    final plain = _plan(text, width);
    final centered = _plan(text, width, center: true);
    expect(centered.visualLineBreakOffsets, plain.visualLineBreakOffsets);
    expect(plain.visualLineBreakOffsets, isNotEmpty);

    final paragraph = _draw(text, width, center: true);
    expect(
      paragraph.numberOfLines,
      plain.visualLineBreakOffsets.length + 1,
      reason: '置中後畫出來的行數仍和折行計畫一致',
    );
    // 最後一行沒排滿，往中間移。
    final lastStart = plain.visualLineBreakOffsets.last;
    final lastBox = paragraph.getBoxesForRange(
      lastStart + plain.visualLineBreakOffsets.length,
      lastStart + plain.visualLineBreakOffsets.length + 1,
    );
    expect(lastBox.single.left, greaterThan(0));
    paragraph.dispose();
  });

  test('a downloaded font comes after the system font for Latin and before '
      'it for CJK', () {
    final system = HybridBlockTextStyle.fromLayoutStyle(_layoutStyle());
    final kai = HybridBlockTextStyle.fromLayoutStyle(
      _layoutStyle(fontFamily: 'NightReaderWenKaiTC'),
      isTitle: true,
    );
    expect(system.fontFamilyFallback, ['sans-serif']);
    expect(system.cjkFontFamilyFallback, ['sans-serif']);
    // 英數字照舊用系統字型；中日文字讓下載的字型先選，系統字型自帶漢字也輪得到。
    expect(kai.fontFamilyFallback, ['sans-serif', 'NightReaderWenKaiTC']);
    expect(kai.cjkFontFamilyFallback, ['NightReaderWenKaiTC', 'sans-serif']);
  });

  test('only titles take the title weight and alignment', () {
    final style = _layoutStyle(titleBold: false, titleCenter: true);
    final title = HybridBlockTextStyle.fromLayoutStyle(style, isTitle: true);
    final body = HybridBlockTextStyle.fromLayoutStyle(style);
    expect(title.bold, isFalse);
    expect(title.center, isTrue);
    expect(body.bold, isFalse);
    expect(body.center, isFalse);

    final boldBody = HybridBlockTextStyle.fromLayoutStyle(
      _layoutStyle(bold: true),
    );
    expect(boldBody.bold, isTrue);
    expect(
      HybridBlockTextStyle.fromLayoutStyle(
        _layoutStyle(bold: true),
        isTitle: true,
      ).bold,
      isTrue,
    );
  });

  test('weight and title alignment are part of the layout identity', () {
    ReaderV2LayoutSpec spec(ReaderV2LayoutStyle style) =>
        ReaderV2LayoutSpec.fromViewport(
          viewportSize: const ui.Size(393, 800),
          style: style,
        );
    final base = spec(_layoutStyle());
    for (final changed in [
      _layoutStyle(bold: true),
      _layoutStyle(titleBold: false),
      _layoutStyle(titleCenter: true),
      _layoutStyle(fontFamily: 'NightReaderWenKaiTC'),
    ]) {
      final other = spec(changed);
      expect(other.layoutSignature, isNot(base.layoutSignature));
      expect(
        StyleFingerprint.fromLayoutSpec(other).stableKey,
        isNot(StyleFingerprint.fromLayoutSpec(base).stableKey),
      );
    }
  });
}
