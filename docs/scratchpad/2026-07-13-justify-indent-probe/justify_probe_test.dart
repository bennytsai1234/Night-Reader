// 排版探針：驗證 TextAlign.justify 對「烘入段首全形空白縮排」的行為。
//
// 背景：使用者截圖顯示多行段落被大幅撐開且失去縮排，單行段落正常。
// 假設：SkParagraph 的 justify 把行首 U+3000 當可分配空白吃掉，
//       並把該寬度平均分進整行字距。
//
// 執行：flutter test docs/scratchpad/2026-07-13-justify-indent-probe/justify_probe_test.dart
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

const _indent = '　　'; // U+3000 x2，與 reader_v2_content_transformer 烘入的相同
const _body = '衝在最前面的妖怪頭顱便滾落在地。';
const _fontSize = 20.0;
// 寬度 16.4 字元寬：含縮排時 line1 = 縮排2 + 14字（…在），line2 = 地。
// 與使用者截圖的斷行位置一致，且 line1 有 0.4 字寬的殘餘空隙可供 justify 分配。
const _width = _fontSize * 16.4;

ui.Paragraph _build(String text, ui.TextAlign align) {
  final style = ui.ParagraphStyle(
    textAlign: align,
    textDirection: ui.TextDirection.ltr,
    fontSize: _fontSize,
    height: 1.5,
  );
  final builder =
      ui.ParagraphBuilder(style)
        ..pushStyle(ui.TextStyle(color: const ui.Color(0xFF000000)))
        ..addText(text);
  return builder.build()..layout(const ui.ParagraphConstraints(width: _width));
}

void _dump(String label, String text, ui.TextAlign align) {
  final p = _build(text, align);
  final lines = p.computeLineMetrics();
  // ignore: avoid_print
  print('==== $label（align=$align, width=$_width）====');
  for (var i = 0; i < lines.length; i += 1) {
    final m = lines[i];
    // ignore: avoid_print
    print(
      '  line[$i] left=${m.left.toStringAsFixed(1)} '
      'width=${m.width.toStringAsFixed(1)} hardBreak=${m.hardBreak}',
    );
  }
  // 逐字 box：看每個字元的實際 x 位置與寬度
  final positions = StringBuffer();
  for (var offset = 0; offset < text.length; offset += 1) {
    final boxes = p.getBoxesForRange(offset, offset + 1);
    if (boxes.isEmpty) {
      positions.write('  [$offset]"${text[offset]}" -> (no box)\n');
      continue;
    }
    final b = boxes.first;
    positions.write(
      '  [$offset]"${text[offset]}" x=${b.left.toStringAsFixed(1)}'
      '..${b.right.toStringAsFixed(1)} '
      'w=${(b.right - b.left).toStringAsFixed(1)} '
      'top=${b.top.toStringAsFixed(1)}\n',
    );
  }
  // ignore: avoid_print
  print(positions.toString());
}

ui.Paragraph _buildWithPlaceholders(String body, ui.TextAlign align) {
  final style = ui.ParagraphStyle(
    textAlign: align,
    textDirection: ui.TextDirection.ltr,
    fontSize: _fontSize,
    height: 1.5,
  );
  final builder =
      ui.ParagraphBuilder(style)
        ..pushStyle(ui.TextStyle(color: const ui.Color(0xFF000000)));
  for (var i = 0; i < 2; i += 1) {
    builder.addPlaceholder(
      _fontSize,
      _fontSize,
      ui.PlaceholderAlignment.bottom,
    );
  }
  builder.addText(body);
  return builder.build()..layout(const ui.ParagraphConstraints(width: _width));
}

void _dumpPlaceholder(String label, String body, ui.TextAlign align) {
  final p = _buildWithPlaceholders(body, align);
  final lines = p.computeLineMetrics();
  // ignore: avoid_print
  print('==== $label（placeholder 縮排, align=$align, width=$_width）====');
  for (var i = 0; i < lines.length; i += 1) {
    final m = lines[i];
    // ignore: avoid_print
    print(
      '  line[$i] left=${m.left.toStringAsFixed(1)} '
      'width=${m.width.toStringAsFixed(1)} '
      'height=${m.height.toStringAsFixed(1)} hardBreak=${m.hardBreak}',
    );
  }
  final placeholderBoxes = p.getBoxesForPlaceholders();
  for (final b in placeholderBoxes) {
    // ignore: avoid_print
    print(
      '  placeholder x=${b.left.toStringAsFixed(1)}..'
      '${b.right.toStringAsFixed(1)} w=${(b.right - b.left).toStringAsFixed(1)}',
    );
  }
  final text = '￼￼$body';
  final positions = StringBuffer();
  for (var offset = 0; offset < text.length; offset += 1) {
    final boxes = p.getBoxesForRange(offset, offset + 1);
    if (boxes.isEmpty) {
      positions.write('  [$offset] -> (no box)\n');
      continue;
    }
    final b = boxes.first;
    positions.write(
      '  [$offset]"${text[offset]}" x=${b.left.toStringAsFixed(1)}'
      '..${b.right.toStringAsFixed(1)} '
      'w=${(b.right - b.left).toStringAsFixed(1)} '
      'top=${b.top.toStringAsFixed(1)}\n',
    );
  }
  // ignore: avoid_print
  print(positions.toString());
}

void main() {
  test('justify 與 start 對含縮排段落的排版差異', () {
    _dump('含縮排 + start', '$_indent$_body', ui.TextAlign.start);
    _dump('含縮排 + justify', '$_indent$_body', ui.TextAlign.justify);
    _dump('無縮排 + justify', _body, ui.TextAlign.justify);
    _dump('單行 + justify', '$_indent韓採妍趁機箭步上前。', ui.TextAlign.justify);
  });

  test('placeholder 縮排 + justify：縮排不被折疊、行高不變', () {
    _dumpPlaceholder('多行段落', _body, ui.TextAlign.justify);
    _dumpPlaceholder('單行段落', '韓採妍趁機箭步上前。', ui.TextAlign.justify);
  });

  // 末行補償 off-by-one 疑點：headroom 以 gaps（字數-1）為分母，但
  // letterSpacing 加在每個字後（字數份）——總增量 = spacing×字數 >
  // headroom，幾乎滿行的末行是否被擠到回捲？
  test('末行補償 off-by-one：近滿末行 + clamp 到 headroom/gaps 是否回捲', () {
    const chars = 27; // 9/9/9 三行，無標點避免避頭尾干擾
    final text = '夜' * chars;
    const width = _fontSize * 9 + 1; // 每行 9 字 + 1px 殘餘
    // Pass 2 模擬：末行 [18,27) 套 extraLetterSpacing = headroom/gaps
    const spacing = 1.0 / 8; // headroom 1px / gaps 8
    final style = ui.ParagraphStyle(
      textAlign: ui.TextAlign.justify,
      textDirection: ui.TextDirection.ltr,
      fontSize: _fontSize,
      height: 1.5,
    );
    final builder =
        ui.ParagraphBuilder(style)
          ..pushStyle(ui.TextStyle(color: const ui.Color(0xFF000000)))
          ..addText(text.substring(0, 18))
          ..pushStyle(
            ui.TextStyle(
              color: const ui.Color(0xFF000000),
              letterSpacing: spacing,
            ),
          )
          ..addText(text.substring(18))
          ..pop();
    final p =
        builder.build()..layout(const ui.ParagraphConstraints(width: width));
    final lines = p.computeLineMetrics();
    // ignore: avoid_print
    print('==== 末行補償 off-by-one 探針（width=$width, spacing=$spacing）====');
    for (var i = 0; i < lines.length; i += 1) {
      // ignore: avoid_print
      print(
        '  line[$i] width=${lines[i].width.toStringAsFixed(2)} '
        'hardBreak=${lines[i].hardBreak}',
      );
    }
    // ignore: avoid_print
    print('  lineCount=${lines.length}（3=安全, 4=末字回捲）');
  });
}
