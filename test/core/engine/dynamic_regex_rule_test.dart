import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/analyze_rule.dart';
import 'package:night_reader/core/models/book_source.dart';

import '../../test_helper.dart';

/// 含 `{{ }}`、`@get:` 的規則照 Legado 組好後當正則模式的規則用：在內容裡
/// 找不到就是沒有結果，不拿組好的規則文字當結果（`AnalyzeRule.getElement`／
/// `getElements`，Legado 沒有這個退回）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupTestDI();

  AnalyzeRule rule(String content) =>
      AnalyzeRule(source: BookSource(bookSourceUrl: 'https://r.test'))
          .setContent(content, baseUrl: 'https://r.test/list');

  const html = '<ul><li>甲</li><li>乙</li></ul>';

  test('getElements 沒找到是空的，不是規則文字', () {
    expect(rule(html).getElements("{{'沒有這個'}}"), isEmpty);

    final byVariable = rule(html)..put('keyword', '沒有這個');
    expect(byVariable.getElements('@get:{keyword}'), isEmpty);
  });

  test('getElement 沒找到是空的，書籍詳情的 init 不會被規則文字換掉', () {
    expect(rule(html).getElement("{{'沒有這個'}}"), isNull);

    final byVariable = rule(html)..put('keyword', '沒有這個');
    expect(byVariable.getElement('@get:{keyword}'), isNull);
  });

  test('找得到時照舊', () {
    expect(rule(html).getElements("{{'<li>.*?</li>'}}"), isNotEmpty);
    expect(rule(html).getElement("{{'<li>(.*?)</li>'}}"), '<li>甲</li>甲');
  });

  test('getString 照舊：組好的文字就是結果', () {
    expect(rule(html).getString("前{{'沒有這個'}}後"), '前沒有這個後');
  });
}
