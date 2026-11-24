import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/analyze_rule.dart';
import 'package:night_reader/core/models/source/book_source.dart';

import '../../../test_helper.dart';

/// JSON 路徑對到的值是陣列時，Legado 一項一行接起來
/// （`AnalyzeByJSonPath.getString` 的 `ob.joinToString("\n")`）；空陣列是空字串，
/// `||` 的下一條規則照樣接手。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupTestDI();

  AnalyzeRule rule(String json) =>
      AnalyzeRule(source: BookSource(bookSourceUrl: 'https://q.test'))
          .setContent(json, baseUrl: 'https://q.test/c/1');

  test('an array field reads one item per line', () {
    expect(
      rule('{"content": ["第一段", "第二段"]}').getString(r'$.content'),
      '第一段\n第二段',
    );
    expect(rule('{"tags": ["玄幻", 3]}').getString(r'$.tags'), '玄幻\n3');
  });

  test('an empty array is empty and lets the next || rule answer', () {
    expect(rule('{"content": []}').getString(r'$.content'), '');
    expect(
      rule('{"content": [], "text": "正文"}').getString(r'$.content||$.text'),
      '正文',
    );
  });
}
