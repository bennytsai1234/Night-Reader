// 一個看得到的字可能佔好幾個 UTF-16 單位（😀、𠮷、👩‍💻）：長按選字、點標註與
// 還原閱讀位置量字的框時，要量整個字，量半個字拿不到框。

import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader/text_view/geometry/text_geometry.dart';

void main() {
  /// 測試字型每個字一格（20px）；寬 100 一行五格。
  ui.Paragraph paragraphOf(String text) {
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: 20))
      ..pushStyle(ui.TextStyle(fontSize: 20))
      ..addText(text);
    return builder.build()..layout(const ui.ParagraphConstraints(width: 100));
  }

  for (final glyph in ['😀', '𠮷', '👩‍💻']) {
    test('$glyph：落在字的哪個單位都拿到整個字的範圍與框', () {
      final paragraph = paragraphOf('甲$glyph乙');
      addTearDown(paragraph.dispose);
      for (var offset = 1; offset <= glyph.length; offset++) {
        final range = TextGeometry.glyphRangeAt(paragraph, offset);
        expect((range.start, range.end), (1, 1 + glyph.length));
        expect(TextGeometry.glyphBoxesAt(paragraph, offset), isNotEmpty);
      }
    });

    test('$glyph 在段落第二行：量得到它那一行的頂', () {
      final paragraph = paragraphOf('甲乙丙丁戊$glyph己');
      addTearDown(paragraph.dispose);
      final top = TextGeometry.textBoxTopForOffset(
        paragraph,
        5,
        7 + glyph.length,
      );
      expect(top, 20);
    });
  }
}
