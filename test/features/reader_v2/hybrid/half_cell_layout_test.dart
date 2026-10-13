import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/reader_v2/hybrid/layout/reader_paragraph_layout.dart';
import 'package:night_reader/features/reader_v2/hybrid/layout/visual_line_layout_engine.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_typography.dart';

/// 英數字段補到半格、emoji 佔一格、行高固定。
///
/// 測試字型（`test/fixtures/fonts/mixed_width_test.ttf`）的字寬：漢字與
/// 全形標點 1000、英文字母 500、i 與 l 250、數字 600、空格 250、😀 1200。
/// 字級 20，所以一格 20px、半格 10px、最小間隙 1/8 格 = 2.5px。
const double _cell = 20;
const _style = HybridBlockTextStyle(
  fontSize: _cell,
  lineHeight: 1.5,
  letterSpacing: 0,
);
const _engine = VisualLineLayoutEngine();
const _layout = ReaderParagraphLayout();

VisualLineBlockPlan _plan(String text, double width, {int indent = 0}) =>
    _engine.planBlock(
      text: text,
      start: 0,
      maxBlockChars: 10000,
      textStyle: _style,
      contentWidth: width,
      cellWidth: _cell,
      indentChars: indent,
    );

/// 依 [plan] 畫出的 Paragraph 與換算表。
({ui.Paragraph paragraph, ParagraphTextMap map}) _draw(
  String text,
  VisualLineBlockPlan plan,
  double width, {
  int indent = 0,
}) {
  final map = ParagraphTextMap(
    sourceLength: text.length,
    indentLength: indent,
    visualLineBreakOffsets: plan.visualLineBreakOffsets,
    spacers: plan.spacers,
  );
  final paragraph = _layout.build(
    sourceText: text,
    textMap: map,
    textStyle: _style,
    contentWidth: width,
    cellWidth: _cell,
    textColor: const ui.Color(0xFF000000),
  );
  expect(
    paragraph.numberOfLines,
    plan.visualLineBreakOffsets.length + 1,
    reason: '畫出來的行數要和換行計畫一致，不能多出自動換行',
  );
  return (paragraph: paragraph, map: map);
}

/// 來源位置 [offset] 起 [length] 個 UTF-16 單位那個字的框。
ui.TextBox _box(
  ({ui.Paragraph paragraph, ParagraphTextMap map}) drawn,
  int offset, {
  int length = 1,
}) {
  final range = drawn.map.paragraphRangeForSourceRange(offset, offset + length);
  return drawn.paragraph.getBoxesForRange(range.start, range.end).first;
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

  test('英數字段夾在漢字中間時補到半格，補白平分兩側', () {
    const text = '一二abc三四';
    final plan = _plan(text, 200);
    // abc 寬 30，加上兩側最小間隙 5 是 35，補到 40：每側 5。
    expect(plan.spacers, const [LineSpacer(2, 5), LineSpacer(5, 5)]);
    final drawn = _draw(text, plan, 200);
    expect(_box(drawn, 2).left, closeTo(45, 0.01));
    expect(_box(drawn, 5).left, closeTo(80, 0.01), reason: '「三」回到字格上');
  });

  test('數字也補到半格', () {
    const text = '一3二';
    final plan = _plan(text, 200);
    // 3 寬 12，加間隙 17，補到 20：每側 4。
    expect(plan.spacers, const [LineSpacer(1, 4), LineSpacer(2, 4)]);
    expect(_box(_draw(text, plan, 200), 2).left, closeTo(40, 0.01));
  });

  test('另一側不需要間隙時，漢字側仍至少 1/8 格', () {
    // 123 寬 36：補到 40 共 4，平分是每側 2，低於漢字側的 2.5。
    expect(_plan('一123', 200).spacers, const [LineSpacer(1, 2.5)]);
    const text = '「123一';
    final plan = _plan(text, 200);
    expect(plan.spacers, const [LineSpacer(1, 1.5), LineSpacer(4, 2.5)]);
    expect(_box(_draw(text, plan, 200), 4).left, closeTo(60, 0.01));
  });

  test('行首的英數字段貼齊左邊界，補白全放右側', () {
    const text = 'abc一二';
    final plan = _plan(text, 200);
    expect(plan.spacers, const [LineSpacer(3, 10)]);
    final drawn = _draw(text, plan, 200);
    expect(_box(drawn, 0).left, closeTo(0, 0.01));
    expect(_box(drawn, 3).left, closeTo(40, 0.01));
  });

  test('段首縮排之後也算行首', () {
    const text = 'abc一';
    final plan = _plan(text, 200, indent: 2);
    expect(plan.spacers, const [LineSpacer(3, 10)]);
    final drawn = _draw(text, plan, 200, indent: 2);
    expect(_box(drawn, 0).left, closeTo(40, 0.01), reason: '緊貼兩格縮排');
    expect(_box(drawn, 3).left, closeTo(80, 0.01));
  });

  test('行尾的英數字段不補右側', () {
    const text = '一二三abc四';
    final plan = _plan(text, 100);
    expect(plan.visualLineBreakOffsets, const [6]);
    expect(plan.spacers, const [LineSpacer(3, 5)]);
    final drawn = _draw(text, plan, 100);
    expect(_box(drawn, 6).left, closeTo(0, 0.01));
  });

  test('鄰接全形標點的一側不另外留間隙', () {
    const text = '「abc」';
    final plan = _plan(text, 200);
    // 30 已是半格的倍數，兩側都是標點，不補。
    expect(plan.spacers, isEmpty);
    expect(_box(_draw(text, plan, 200), 4).left, closeTo(50, 0.01));
  });

  test('放不下的英文從字的開頭換行，下一行的字仍落在字格上', () {
    const text = '一abcdefgh ijklmn二';
    final plan = _plan(text, 120);
    expect(plan.visualLineBreakOffsets, const [10], reason: '從 ijklmn 開頭換行');
    // 第一行：abcdefgh（+空格）左側補 5；第二行 ijklmn 在行首，寬 50，
    // 右側補到 60。
    expect(plan.spacers, const [LineSpacer(1, 5), LineSpacer(16, 10)]);
    final drawn = _draw(text, plan, 120);
    expect(_box(drawn, 10).left, closeTo(0, 0.01));
    expect(_box(drawn, 16).left, closeTo(60, 0.01));
  });

  test('emoji 縮到剛好一格', () {
    const text = '一\u{1F600}二';
    final plan = _plan(text, 200);
    expect(plan.spacers, isEmpty, reason: 'emoji 佔一格，不當成英數字段');
    final drawn = _draw(text, plan, 200);
    final emoji = _box(drawn, 1, length: 2);
    expect(emoji.right - emoji.left, closeTo(_cell, 0.01));
    expect(_box(drawn, 3).left, closeTo(40, 0.01));
  });

  test('夾著英數字或 emoji 的行，行高與純中文行相同', () {
    const text = '一二三四五abc六\u{1F600}七八';
    final plan = _plan(text, 100);
    expect(plan.visualLineBreakOffsets, isNotEmpty);
    final drawn = _draw(text, plan, 100);
    final heights = {
      for (final line in drawn.paragraph.computeLineMetrics())
        line.height.toStringAsFixed(3),
    };
    expect(heights, hasLength(1));
    expect(double.parse(heights.single), closeTo(_cell * 1.5, 0.01));
  });

  test('emojiRuns 找出 emoji 的範圍，文字樣式的符號不算', () {
    expect(emojiRuns('a\u{1F600}b'), [(start: 1, end: 3)]);
    expect(emojiRuns('\u{1F44D}\u{1F3FD}'), [(start: 0, end: 4)], reason: '膚色');
    expect(emojiRuns('\u{1F1F9}\u{1F1FC}\u{1F1EF}\u{1F1F5}'), [
      (start: 0, end: 8),
    ], reason: '兩面國旗相連');
    expect(emojiRuns('1️⃣'), [(start: 0, end: 3)], reason: '鍵帽');
    expect(emojiRuns('❤️'), [(start: 0, end: 2)], reason: 'FE0F');
    expect(emojiRuns('© 2024 ™'), isEmpty);
    expect(emojiRuns('第3章'), isEmpty);
  });
}
