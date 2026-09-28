import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_typography.dart';

/// 章節交界的留白契約：章末 block 在一般段距之外多出固定行數的空白。
///
/// 空白計入章末 block 的 trailingSpacing，而 block 高度等於排版高度加
/// trailingSpacing（hybrid_pump_test 驗證），因此捲動、定位與進度共用
/// 同一份幾何。
void main() {
  const style = ReaderV2LayoutStyle(
    fontSize: 20,
    lineHeight: 1.5,
    letterSpacing: 0,
    paragraphSpacing: 1.0,
    paddingTop: 0,
    paddingBottom: 0,
    paddingLeft: 16,
    paddingRight: 16,
  );
  const lineExtent = 30.0;

  test('chapter end adds the gap on top of the paragraph spacing', () {
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
    expect(paragraph, lineExtent);
    expect(chapterEnd - paragraph, lineExtent * kReaderV2ChapterGapLines);
  });

  test('a title-only chapter still separates from the next chapter', () {
    final title = readerV2BlockTrailingSpacing(
      style,
      isTitle: true,
      isChapterEnd: false,
    );
    final titleAtEnd = readerV2BlockTrailingSpacing(
      style,
      isTitle: true,
      isChapterEnd: true,
    );
    expect(titleAtEnd - title, lineExtent * kReaderV2ChapterGapLines);
  });
}
