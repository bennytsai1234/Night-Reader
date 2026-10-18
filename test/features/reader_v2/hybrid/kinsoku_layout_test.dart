import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/reader_v2/hybrid/layout/reader_paragraph_layout.dart';
import 'package:night_reader/features/reader_v2/hybrid/layout/visual_line_layout_engine.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_typography.dart';

/// 換行做避頭尾，被拉字的行把空隙攤進字距（ADR 0026）。
///
/// 測試字型（`test/fixtures/fonts/mixed_width_test.ttf`）：漢字與全形標點
/// 1000、英文字母 500，字級 20，所以一格 20px。文字框寬 100 是五格。
const double _cell = 20;
const double _width = 100;
const _style = HybridBlockTextStyle(
  fontSize: _cell,
  lineHeight: 1.5,
  letterSpacing: 0,
);
const _engine = VisualLineLayoutEngine();
const _layout = ReaderParagraphLayout();

VisualLineBlockPlan _plan(String text) => _engine.planBlock(
  text: text,
  start: 0,
  maxBlockChars: 10000,
  textStyle: _style,
  contentWidth: _width,
  cellWidth: _cell,
  indentChars: 0,
);

Matcher _spacers(List<LineSpacer> expected) =>
    pairwiseCompare<LineSpacer, LineSpacer>(
      expected,
      (e, a) => e.offset == a.offset && (e.width - a.width).abs() < 0.001,
      'spacers within 0.001px of',
    );

/// 依 [plan] 畫出 Paragraph，回傳來源位置 [offset] 那個字的框。
ui.TextBox _box(String text, VisualLineBlockPlan plan, int offset) {
  final map = ParagraphTextMap(
    sourceLength: text.length,
    indentLength: 0,
    visualLineBreakOffsets: plan.visualLineBreakOffsets,
    spacers: plan.spacers,
  );
  final paragraph = _layout.build(
    sourceText: text,
    textMap: map,
    textStyle: _style,
    contentWidth: _width,
    cellWidth: _cell,
    textColor: const ui.Color(0xFF000000),
  );
  expect(
    paragraph.numberOfLines,
    plan.visualLineBreakOffsets.length + 1,
    reason: '攤進字距的行不能被原生排版再折一次',
  );
  final range = map.paragraphRangeForSourceRange(offset, offset + 1);
  return paragraph.getBoxesForRange(range.start, range.end).first;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final bytes = File('test/fixtures/fonts/mixed_width_test.ttf')
        .readAsBytesSync();
    final loader = FontLoader(kReaderV2PunctFontFamily)
      ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    await loader.load();
  });

  test('收尾標點不放行首：前一個字陪它換行，空隙攤進字距', () {
    const text = '一二三四五。六';
    final plan = _plan(text);
    expect(plan.visualLineBreakOffsets, const [4]);
    // 一二三四佔四格，空出的一格平分給三個字距。
    const gap = _cell / 3;
    expect(
      plan.spacers,
      _spacers(const [
        LineSpacer(1, gap),
        LineSpacer(2, gap),
        LineSpacer(3, gap),
      ]),
    );
    expect(_box(text, plan, 3).right, closeTo(_width, 0.01), reason: '右緣切齊');
    expect(_box(text, plan, 4).left, closeTo(0, 0.01));
  });

  test('開頭引號不放行尾', () {
    const text = '一二三四「五六」';
    final plan = _plan(text);
    expect(plan.visualLineBreakOffsets, const [4]);
    expect(_box(text, plan, 4).left, closeTo(0, 0.01));
  });

  test('兩個收尾標點連在一起時拉兩個字', () {
    const text = '一二三四。」五';
    final plan = _plan(text);
    expect(plan.visualLineBreakOffsets, const [3]);
    expect(
      plan.spacers,
      _spacers(const [LineSpacer(1, _cell), LineSpacer(2, _cell)]),
    );
    expect(_box(text, plan, 2).right, closeTo(_width, 0.01));
  });

  test('刪節號與破折號成對不拆', () {
    expect(_plan('一二三四……五').visualLineBreakOffsets, const [4]);
    expect(_plan('一二三四——五').visualLineBreakOffsets, const [4]);
  });

  test('整段英數字當成一個字一起拉', () {
    // 一二三之後的 ab 補到 30，再接「」」就放不下。
    const text = '一二三ab」四';
    final plan = _plan(text);
    expect(plan.visualLineBreakOffsets, const [3]);
    expect(_box(text, plan, 3).left, closeTo(0, 0.01), reason: 'ab 移到下一行行首');
    expect(_box(text, plan, 2).right, closeTo(_width, 0.01));
  });

  test('英文單字裡面不拉開字距', () {
    // 一 ab 二 三 。：三陪句號換行，空出的 30 只攤在漢字旁的兩個字距。
    const text = '一ab二三。';
    final plan = _plan(text);
    expect(plan.visualLineBreakOffsets, const [4]);
    expect(
      plan.spacers,
      _spacers(const [LineSpacer(1, 20), LineSpacer(3, 20)]),
    );
    final a = _box(text, plan, 1);
    final b = _box(text, plan, 2);
    expect(b.left, closeTo(a.right, 0.01), reason: 'a、b 之間沒有補白');
    expect(_box(text, plan, 3).right, closeTo(_width, 0.01));
  });

  test('要把整行拉空或拉太多字時照原本的位置斷', () {
    expect(_plan('。。。。。。').visualLineBreakOffsets, const [5]);
  });
}
