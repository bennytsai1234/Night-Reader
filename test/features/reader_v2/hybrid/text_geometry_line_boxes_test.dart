// 朗讀高亮與選字反白的框照視覺行併成一行一個：對齊補白（零高度的佔位格）
// 不能把下一行的框撐寬。

import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/hybrid/geometry/text_geometry.dart';

void main() {
  /// 測試字型每個字一格（20px）；寬 200 一行十個字，二十個字排成兩行。
  ui.Paragraph twoLines() {
    final builder =
        ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: 20, height: 1.5))
          ..pushStyle(ui.TextStyle(fontSize: 20, height: 1.5))
          ..addText('字' * 20);
    return builder.build()..layout(const ui.ParagraphConstraints(width: 200));
  }

  test('對齊補白落在下一行頂端時，下一行的框不被它撐寬', () {
    final paragraph = twoLines();
    addTearDown(paragraph.dispose);
    expect(paragraph.numberOfLines, 2);
    final second = paragraph.getLineMetricsAt(1)!;
    final secondTop = second.baseline - second.ascent;
    // 第二行只到第十二個字：左右是 0 到 40。
    final glyphs = paragraph.getBoxesForRange(0, 12);
    // 第一行的補白（零高度）在行底；手機的字型量起來會比下一行的頂端
    // 低一點點。
    final spacer = ui.TextBox.fromLTRBD(
      60,
      secondTop + 1,
      150,
      secondTop + 1,
      ui.TextDirection.ltr,
    );

    final lines = HybridTextGeometry.boxesPerLine(paragraph, [
      ...glyphs,
      spacer,
    ]);

    expect(lines, hasLength(2));
    expect(lines.first.left, 0);
    expect(lines.first.right, 200);
    expect(lines.last.left, 0);
    expect(lines.last.right, 40, reason: '第二行只框到第十二個字，不包含上一行的補白');
  });
}
