import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// loadScreenshotFonts 要系統的中文字型，CI 的 Linux 沒有裝（AGENTS.md「環境」）。
// 一般測試用了，在 Windows 上本機全過，推上去 CI 才紅（#102）；所以只留給截圖與
// 量幀數這兩組平常跳過的測試。
const _allowed = [
  'test/screens/',
  'test/_screens/',
  'test/frame_budget/',
  'test/support/screenshot.dart',
];

// 呼叫或當成 setUpAll 的參數傳進去；只在說明裡提到不算。
final _use = RegExp(r'loadScreenshotFonts\s*[(),]');

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
              _use.hasMatch(File(path).readAsStringSync()),
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
