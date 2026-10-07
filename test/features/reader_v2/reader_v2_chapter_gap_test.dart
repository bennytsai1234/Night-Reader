import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_typography.dart';

/// 章節交界的留白契約：章末 block 至少留固定行數的空白，不疊加段距。
///
/// 空白計入章末 block 的 trailingSpacing，而 block 高度等於排版高度加
/// trailingSpacing（hybrid_pump_test 驗證），因此捲動、定位與進度共用
/// 同一份幾何。
void main() {
  ReaderV2LayoutStyle styleWith(double paragraphSpacing) => ReaderV2LayoutStyle(
    fontSize: 20,
    lineHeight: 1.5,
    letterSpacing: 0,
    paragraphSpacing: paragraphSpacing,
    paddingTop: 0,
    paddingBottom: 0,
    paddingLeft: 16,
    paddingRight: 16,
  );
  const lineExtent = 30.0;

  test('chapter end leaves exactly the gap lines with default spacing', () {
    final chapterEnd = readerV2BlockTrailingSpacing(
      styleWith(1.0),
      isTitle: false,
      isChapterEnd: true,
    );
    expect(chapterEnd, lineExtent * kReaderV2ChapterGapLines);
  });

  test('tight paragraph spacing still leaves the chapter gap', () {
    final style = styleWith(0.3);
    final paragraph = readerV2BlockTrailingSpacing(
      style,
      isTitle: false,
      isChapterEnd: false,
    );
    final chapterEnd = readerV2BlockTrailingSpacing(
      style,
      isTitle: false,
      isChapterEnd: true,
    );
    expect(paragraph, lessThan(chapterEnd));
    expect(chapterEnd, lineExtent * kReaderV2ChapterGapLines);
  });

  test('wide paragraph spacing is not stacked on top of the gap', () {
    final style = styleWith(2.0);
    final paragraph = readerV2BlockTrailingSpacing(
      style,
      isTitle: false,
      isChapterEnd: false,
    );
    final chapterEnd = readerV2BlockTrailingSpacing(
      style,
      isTitle: false,
      isChapterEnd: true,
    );
    expect(chapterEnd, paragraph);
  });

  test('a title-only chapter still separates from the next chapter', () {
    final titleAtEnd = readerV2BlockTrailingSpacing(
      styleWith(1.0),
      isTitle: true,
      isChapterEnd: true,
    );
    expect(titleAtEnd, lineExtent * kReaderV2ChapterGapLines);
  });
}
