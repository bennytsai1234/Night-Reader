import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/analyze_rule.dart';
import 'package:night_reader/core/models/book_source.dart';

import '../../test_helper.dart';

/// 規則 JS 交回的整數值不能變成 `11702988684.0`。QuickJS 的數字超過 32 位元
/// 整數就以浮點數交出，Lofter 目錄規則經過一段 JS 之後，貼文編號 `id` 組進
/// 正文網址就成了 `postid=11702988684.0`，網站回 500。Legado 的 Rhino 把資料
/// 物件原樣留在 Java 裡（Long），`{{js}}` 的數字也用 `%.0f` 印成整數。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupTestDI();

  AnalyzeRule rule() =>
      AnalyzeRule(source: BookSource(bookSourceUrl: 'https://l.test'))
          .setContent(
            '{"list":[{"id":11702988684,"n":5,"f":1.5}]}',
            baseUrl: 'https://l.test/x',
          );

  test('JS 交回的資料物件，大整數仍是整數', () {
    final items = rule().getElements('\$.list[*]\n<js>\nresult\n</js>\n\$.[*]');
    expect(items.single, {'id': 11702988684, 'n': 5, 'f': 1.5});
    expect((items.single as Map)['id'], isA<int>());
  });

  test('目錄經過 JS 後，用 {{}} 組出的網址沒有 .0', () {
    final item = rule()
        .getElements('\$.list[*]\n<js>\nresult\n</js>\n\$.[*]')
        .single;
    final url = AnalyzeRule(source: BookSource(bookSourceUrl: 'https://l.test'))
        .setContent(item, baseUrl: 'https://l.test/x')
        .getString(r'postid={{$.id}}');
    expect(url, 'postid=11702988684');
  });

  test('JS 算出的整數值當文字用沒有 .0，小數照舊', () {
    expect(rule().getString('@js:11702988684'), '11702988684');
    expect(rule().getString('{{11702988684 + 1}}'), '11702988685');
    expect(rule().getString('@js:1.5 * 3'), '4.5');
  });
}
