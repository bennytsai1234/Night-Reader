import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart' show Size;
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';

/// 章節交界的留白契約：章末 block 留下使用者設定的章節間距（行），
/// 與段距分開計算、不疊加。
///
/// 空白計入章末 block 的 trailingSpacing，而 block 高度等於排版高度加
/// trailingSpacing（hybrid_pump_test 驗證），因此捲動、定位與進度共用
/// 同一份幾何。
void main() {
  ReaderV2LayoutStyle styleWith({
    double paragraphSpacing = 1.0,
    double chapterSpacing = 1.0,
  }) => ReaderV2LayoutStyle(
    fontSize: 20,
    lineHeight: 1.5,
    letterSpacing: 0,
    paragraphSpacing: paragraphSpacing,
    chapterSpacing: chapterSpacing,
    paddingTop: 0,
    paddingBottom: 0,
    paddingLeft: 16,
    paddingRight: 16,
  );
  const lineExtent = 30.0;

  double chapterEnd(ReaderV2LayoutStyle style, {bool isTitle = false}) =>
      readerV2BlockTrailingSpacing(
        style,
        isTitle: isTitle,
        isChapterEnd: true,
      );

  test('chapter end leaves exactly the configured lines', () {
    expect(chapterEnd(styleWith()), lineExtent);
    expect(chapterEnd(styleWith(chapterSpacing: 2.5)), lineExtent * 2.5);
    expect(chapterEnd(styleWith(chapterSpacing: 0)), 0);
  });

  test('paragraph spacing does not stack on the chapter gap', () {
    expect(chapterEnd(styleWith(paragraphSpacing: 0.3)), lineExtent);
    expect(chapterEnd(styleWith(paragraphSpacing: 2.0)), lineExtent);
  });

  test('a title-only chapter uses the same chapter gap', () {
    expect(chapterEnd(styleWith(), isTitle: true), lineExtent);
  });

  test('chapter spacing is part of the text layout and cache identity', () {
    ReaderV2LayoutSpec spec(double chapterSpacing) =>
        ReaderV2LayoutSpec.fromViewport(
          viewportSize: const Size(400, 800),
          style: styleWith(chapterSpacing: chapterSpacing),
        );
    final one = spec(1);
    final two = spec(2);
    expect(two.layoutSignature, isNot(one.layoutSignature));
    expect(
      StyleFingerprint.fromLayoutSpec(two),
      isNot(StyleFingerprint.fromLayoutSpec(one)),
    );
  });
}
