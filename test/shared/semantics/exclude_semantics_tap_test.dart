import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `Semantics(button: true, excludeSemantics: true, …)` 把底下手勢元件的
/// 點擊動作一起排除了：讀屏點兩下沒反應。這種按鈕要在同一個 Semantics
/// 自己帶 `onTap`。
void main() {
  test('排除子語意的按鈕自己帶 onTap', () {
    final offenders = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'));
    for (final file in files) {
      final source = file.readAsStringSync();
      for (final match in RegExp(r'Semantics\(').allMatches(source)) {
        final args = _arguments(source, match.end);
        if (args == null) continue;
        // 只看 Semantics 自己的參數，不看 child 裡面。
        final own = args.split(RegExp(r'\bchild:')).first;
        if (!own.contains('excludeSemantics: true')) continue;
        if (!own.contains('button: true')) continue;
        if (own.contains('onTap:')) continue;
        final line = '\n'.allMatches(source.substring(0, match.start)).length;
        offenders.add('${file.path}:${line + 1}');
      }
    }
    expect(offenders, isEmpty);
  });
}

/// 從左括號後到對應右括號之間的文字。
String? _arguments(String source, int start) {
  var depth = 1;
  for (var i = start; i < source.length; i++) {
    final c = source[i];
    if (c == '(') depth++;
    if (c == ')') {
      depth--;
      if (depth == 0) return source.substring(start, i);
    }
  }
  return null;
}
