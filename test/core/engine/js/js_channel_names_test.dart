import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 規則 JS 呼叫 Dart 的頻道名稱不能重複：QuickJS 的頻道已經有同名的就不
/// 換，後註冊的那份靜靜地沒用上（`third_party/flutter_js` 的
/// `quickjs_runtime2.dart`）。
void main() {
  test('every rule JS channel is registered once', () {
    final pattern = RegExp(
      r'''(?:onMessage|onBlocking)\(\s*'([A-Za-z0-9_]+)'\s*,''',
    );
    final seen = <String, List<String>>{};
    final files = Directory('lib/core/engine/js')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    for (final file in files) {
      for (final match in pattern.allMatches(file.readAsStringSync())) {
        seen.putIfAbsent(match.group(1)!, () => []).add(file.path);
      }
    }
    expect(seen, isNotEmpty);
    final duplicates = {
      for (final MapEntry(:key, :value) in seen.entries)
        if (value.length > 1) key: value,
    };
    expect(duplicates, isEmpty);
  });
}
