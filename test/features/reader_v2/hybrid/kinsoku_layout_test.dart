import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/reader_v2/hybrid/layout/reader_paragraph_layout.dart';
import 'package:night_reader/features/reader_v2/hybrid/layout/visual_line_layout_engine.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_typography.dart';

/// 換行做避頭尾，被拉字的行把空隙攤進字距，每個字距最多 1/4 格（ADR 0026）。
///
/// 測試字型（`test/fixtures/fonts/mixed_width_test.ttf`）：漢字與全形標點
/// 1000、英文字母 500、空格 250，字級 20，所以一格 20px。文字框寬 260 是
/// 十三格，和閱讀器一樣再加 0.05 的 slack 防浮點誤差。被拉字的行每個字距
/// 最多多 1/4 格（5px）。
const double _cell = 20;
const double _frame = 260;
const double _width = _frame + 0.05;
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
    const text = '一二三四五六七八九十一二三。四';
    final plan = _plan(text);
    expect(plan.visualLineBreakOffsets, const [12]);
    // 前十二個字佔十二格，空出的一格平分給十一個字距。
    const gap = _cell / 11;
    expect(
      plan.spacers,
      _spacers([for (var i = 1; i <= 11; i++) LineSpacer(i, gap)]),
    );
    expect(_box(text, plan, 11).right, closeTo(_frame, 0.01), reason: '右緣切齊');
    expect(_box(text, plan, 12).left, closeTo(0, 0.01));
  });

  test('開頭引號不放行尾', () {
    const text = '一二三四五六七八九十一二「三四」';
    final plan = _plan(text);
    expect(plan.visualLineBreakOffsets, const [12]);
    expect(_box(text, plan, 12).left, closeTo(0, 0.01));
  });

  test('兩個收尾標點連在一起時拉兩個字', () {
    const text = '一二三四五六七八九十一二。」三';
    final plan = _plan(text);
    expect(plan.visualLineBreakOffsets, const [11]);
    // 十一個字、十個字距，空出的兩格每個字距攤 4px。
    expect(
      plan.spacers,
      _spacers([for (var i = 1; i <= 10; i++) LineSpacer(i, 4)]),
    );
    expect(_box(text, plan, 10).right, closeTo(_frame, 0.01));
  });

  test('刪節號與破折號成對不拆', () {
    expect(_plan('一二三四五六七八九十一二……三').visualLineBreakOffsets, const [12]);
    expect(_plan('一二三四五六七八九十一二——三').visualLineBreakOffsets, const [12]);
  });

  test('整段英數字當成一個字一起拉', () {
    // 十一個字之後的 ab 補到 30，再接「」」就放不下。
    const text = '一二三四五六七八九十一ab」四';
    final plan = _plan(text);
    expect(plan.visualLineBreakOffsets, const [11]);
    expect(_box(text, plan, 11).left, closeTo(0, 0.01), reason: 'ab 移到下一行行首');
    expect(_box(text, plan, 10).right, closeTo(_frame, 0.01));
  });

  test('有空格的英數字段只拉最後一個單字', () {
    // 一到十之後的「ab cd」補到 50，再接「。」就放不下：只有 cd 陪句號
    // 換行，ab 留在本行；行尾的空格不算寬度。
    const text = '一二三四五六七八九十ab cd。十';
    final plan = _plan(text);
    expect(plan.visualLineBreakOffsets, const [13]);
    expect(_box(text, plan, 13).left, closeTo(0, 0.01), reason: 'cd 在下一行行首');
    expect(_box(text, plan, 11).right, closeTo(_frame, 0.01), reason: 'b 切齊右緣');
  });

  test('英文單字裡面不拉開字距', () {
    // 一陪句號換行，空出的 30 只攤在漢字旁的十個字距，a、b 之間不攤。
    const text = '一二三四五六七八九ab十一。';
    final plan = _plan(text);
    expect(plan.visualLineBreakOffsets, const [12]);
    expect(
      plan.spacers,
      _spacers([
        for (var i = 1; i <= 8; i++) LineSpacer(i, 3),
        const LineSpacer(9, 8), // ab 左側補白 5 加上攤的 3
        const LineSpacer(11, 8), // ab 右側補白 5 加上攤的 3
      ]),
    );
    final a = _box(text, plan, 9);
    final b = _box(text, plan, 10);
    expect(b.left, closeTo(a.right, 0.01), reason: 'a、b 之間沒有補白');
    expect(_box(text, plan, 11).right, closeTo(_frame, 0.01));
  });

  test('被拉的是長英文單字時，每個字距最多多 1/4 格，右緣短一截', () {
    // abcdefgh 陪句號換行，本行空出五格；七個字距各攤到 5px 為止。
    const text = '一二三四五六七八abcdefgh。九';
    final plan = _plan(text);
    expect(plan.visualLineBreakOffsets, const [8]);
    expect(
      plan.spacers.where((s) => s.offset < 8),
      _spacers([for (var i = 1; i <= 7; i++) LineSpacer(i, _cell / 4)]),
    );
    expect(_box(text, plan, 7).right, closeTo(8 * _cell + 7 * _cell / 4, 0.01));
    expect(_box(text, plan, 8).left, closeTo(0, 0.01));
  });

  test('留在行尾的英數字段沒有右側補白，那一行仍補到和滿行同一個右緣', () {
    // 「「」被拉到下一行，一到九 abcd 留在本行；abcd 在行尾不補右側。
    const text = '一二三四五六七八九abcd「二三四';
    final plan = _plan(text);
    expect(plan.visualLineBreakOffsets.first, 13);
    expect(_box(text, plan, 12).right, closeTo(_frame, 0.01));
  });

  test('要把整行拉空或拉太多字時照原本的位置斷', () {
    expect(_plan('。' * 14).visualLineBreakOffsets, const [13]);
  });
}
