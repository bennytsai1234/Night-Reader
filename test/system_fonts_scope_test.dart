import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// loadScreenshotFonts 要系統的中文字型，CI 的 Linux 沒有裝（AGENTS.md「環境」）。
// 一般測試用了，在 Windows 上本機全過，推上去 CI 才紅（#102）；所以只留給截圖、
// 量幀數與細節檢查這三組平常跳過的測試。
const _allowed = [
  'test/screens/',
  'test/_screens/',
  'test/frame_budget/',
  'test/polish/',
  'test/support/screenshot.dart',
  // 這支檢查自己的失敗訊息裡有這個名字。
  'test/system_fonts_scope_test.dart',
];

// 呼叫、當成 setUpAll 的參數、先存成變數都算；只在 // 註解裡提到、或名字只是
// 另一個識別字的一部分（例如 fake_loadScreenshotFonts）不算。
final _comment = RegExp(r'//.*');
final _use = RegExp(r'(?<![\w$])loadScreenshotFonts(?![\w$])');

void main() {
  test('只有截圖與量幀數的測試載入系統字型', () {
    final offenders =
        [
          for (final entity in Directory('test').listSync(recursive: true))
            if (entity is File && entity.path.endsWith('.dart'))
              entity.path.replaceAll(r'\', '/'),
        ]..retainWhere(
          (path) =>
              !_allowed.any(path.startsWith) &&
              _use.hasMatch(
                File(path).readAsStringSync().replaceAll(_comment, ''),
              ),
        );
    expect(
      offenders,
      isEmpty,
      reason:
          '這些測試用了 loadScreenshotFonts，CI 上找不到中文字型會失敗。'
          '一般測試用測試預設字型；要量英數字補半格時用 '
          'test/fixtures/fonts/mixed_width_test.ttf（範例在 '
          'test/features/reader_v2/hybrid/half_cell_layout_test.dart）。',
    );
  });
}
