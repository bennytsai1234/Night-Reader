import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/json_read.dart';
import 'package:night_reader/core/models/replace_rule.dart';

/// 外部匯入的文字欄位照 Legado（Gson 的 StringJsonDeserializer）讀。
void main() {
  test('objects and arrays become JSON text, numbers their text', () {
    expect(readJsonString(null), isNull);
    expect(readJsonString('a'), 'a');
    expect(readJsonString(12), '12');
    expect(readJsonString(false), 'false');
    expect(readJsonString({'k': 'v'}), '{"k":"v"}');
    expect(readJsonString(['a', 1]), '["a",1]');
  });

  test('a number JSON cannot write does not stop the import', () {
    // `{"x": 1e400}` 讀進來是 Infinity，jsonEncode 寫不出來。
    final value = jsonDecode('{"x": 1e400}');
    expect(readJsonString(value), '{x: Infinity}');
  });

  test('replace rule text fields written as objects become JSON text', () {
    final rule = ReplaceRule.fromJson({
      'name': 123,
      'pattern': 'a',
      'replacement': {'k': 'v'},
      'scope': ['書甲', '書乙'],
    });
    expect(rule.name, '123');
    expect(rule.replacement, '{"k":"v"}');
    expect(rule.scope, '["書甲","書乙"]');
  });
}
