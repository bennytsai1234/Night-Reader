import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/rule_data_fields.dart';

/// 同一本書好幾章同時抓時，各章在複本上增刪的變數合併回呼叫端（ADR 0028）。
void main() {
  final merge = bookRuleFields['variable']!.merge!;

  test('兩個工作各刪一個鍵，刪光了就是空的，先刪的不會回來', () {
    // 刪 a 的先寫回，current 剩 b；刪 b 的這份 after 還有 a。
    final merged = merge(
      jsonEncode({'b': '2'}),
      jsonEncode({'a': '1', 'b': '2'}),
      jsonEncode({'a': '1'}),
    );
    expect(jsonDecode(merged! as String), isEmpty);
  });

  test('沒有變數的工作照舊交回沒有變數', () {
    expect(merge(null, null, null), isNull);
    expect(merge('', '', ''), '');
  });

  test('別的工作寫的鍵留著，這個工作改的鍵照它', () {
    final merged = merge(
      jsonEncode({'a': '1', 'c': '3'}),
      jsonEncode({'a': '1'}),
      jsonEncode({'a': '9'}),
    );
    expect(jsonDecode(merged! as String), {'a': '9', 'c': '3'});
  });
}
