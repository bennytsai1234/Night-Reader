import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/services/update_service.dart';

void main() {
  test('generated release notes become a plain bullet list', () {
    const body = '''## What's Changed
* chore(deps): upgrade all direct dependencies to latest by @bennytsai1234 in https://github.com/bennytsai1234/Night-Reader/pull/20
* fix(reader): resolve tap, back-key, auto-scroll and TTS interaction conflicts by @bennytsai1234 in https://github.com/bennytsai1234/Night-Reader/pull/22
* release: bump version to 0.3.2+179 by @bennytsai1234 in https://github.com/bennytsai1234/Night-Reader/pull/23


**Full Changelog**: https://github.com/bennytsai1234/Night-Reader/compare/v0.3.1...v0.3.2''';

    expect(
      releaseNotesForDisplay(body),
      '• chore(deps): upgrade all direct dependencies to latest\n'
      '• fix(reader): resolve tap, back-key, auto-scroll and TTS interaction conflicts',
    );
  });
}
