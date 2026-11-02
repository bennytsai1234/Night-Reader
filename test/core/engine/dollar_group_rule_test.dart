import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/analyze_rule.dart';
import 'package:night_reader/core/models/book_source.dart';

import '../../test_helper.dart';

/// 規則裡的 `$1`、`$2`（正則的分組代號）只在上一步交來的是一組分組
/// （清單）時才代換；交來的不是清單，就照原文留著，同 Legado
/// `SourceRule.makeUpRule`（`(result as? List)?.run {…} ?:
/// infoVal.insert(0, ruleParam[index])`）。規則 JS 也一樣：JS 程式碼裡
/// 的 `'$1'` 是 `String.replace` 要的分組代號，不能被丟掉。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupTestDI();

  AnalyzeRule rule(dynamic content) =>
      AnalyzeRule(source: BookSource(bookSourceUrl: 'https://d.test'))
          .setContent(content, baseUrl: 'https://d.test/book');

  test('規則 JS 裡的 \$1 保留原文', () {
    // 章名「第3章 起點」去掉「第…章」，只留數字：replace 的 '$1' 要留到 JS 裡。
    expect(rule('第3章').getString(r'@js:result.replace(/第(\d+)章/, "$1")'), '3');
    expect(rule('甲乙').getString(r'@js:result.replace(/(甲)(乙)/, "$2$1")'), '乙甲');
  });

  test('不是 JS 的規則，上一步交來的不是清單時 \$1 也保留原文', () {
    expect(rule('<p>x</p>').getString(r'價格$1'), r'價格$1');
  });

  test('上一步交來一組分組時照舊代換', () {
    expect(rule(['全部', '第一組', '第二組']).getString(r'$2-$1'), '第二組-第一組');
    // 分組不夠多的代號是空的（同 Legado：清單裡沒有就丟掉）
    expect(rule(['全部', '第一組']).getString(r'$1/$2'), '第一組/');
    // JS 拿到清單時也代換
    expect(rule(['全部', '第一組']).getString(r'@js:"$1"'), '第一組');
  });

  test(r'$0 照原文', () {
    expect(rule('abc').getString(r'@js:"$0"'), r'$0');
  });
}
