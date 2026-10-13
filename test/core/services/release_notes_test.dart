import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/services/update_service.dart';

void main() {
  test('changelog notes keep the intro and turn the list into bullets', () {
    const body = '''

這一版讓書架自己保持最新。


- 開 App 時會**自動**檢查新章節。
* 新增「`更新紀錄`」，見[說明](https://example.com/help)。
### 修正
+ 下載不再重複。

''';

    expect(
      releaseNotesForDisplay(body),
      '這一版讓書架自己保持最新。\n'
      '\n'
      '• 開 App 時會自動檢查新章節。\n'
      '• 新增「更新紀錄」，見說明。\n'
      '修正\n'
      '• 下載不再重複。',
    );
  });

  test('older generated notes are shown as they are, without markdown', () {
    const body = '''## What's Changed
* fix(reader): keep place by @a in https://github.com/x/pull/22

**Full Changelog**: https://github.com/x/compare/v0.3.1...v0.3.2''';

    expect(
      releaseNotesForDisplay(body),
      "What's Changed\n"
      '• fix(reader): keep place by @a in https://github.com/x/pull/22\n'
      '\n'
      'Full Changelog: https://github.com/x/compare/v0.3.1...v0.3.2',
    );
  });

  test('empty or blank notes stay empty', () {
    expect(releaseNotesForDisplay(''), '');
    expect(releaseNotesForDisplay('\n  \n'), '');
  });
}
