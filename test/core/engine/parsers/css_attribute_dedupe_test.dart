import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/analyze_rule.dart';
import 'package:night_reader/core/models/source/book_source.dart';

import '../../../test_helper.dart';

/// 取屬性的規則照 Legado `AnalyzeByJSoup.getResultLast`：同一個值只留一個
/// （`textS.contains(url)` 就跳過），文字不去重。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupTestDI();

  const html = '''
<div class="kind">
  <span title="玄幻">玄幻</span><span title="玄幻">玄幻</span><span title="仙俠">仙俠</span>
</div>
<div class="pic"><img src="/a.jpg"><img src="/a.jpg"><img src="/b.jpg"></div>
''';

  AnalyzeRule rule() =>
      AnalyzeRule(source: BookSource(bookSourceUrl: 'https://n.test'))
          .setContent(html, baseUrl: 'https://n.test/book/1');

  test('取屬性時重複的值只留一個', () {
    expect(rule().getStringList('class.kind@tag.span@title'), ['玄幻', '仙俠']);
    expect(rule().getStringList('class.pic@tag.img@src'), ['/a.jpg', '/b.jpg']);
    expect(rule().getString('class.kind@tag.span@title'), '玄幻\n仙俠');
  });

  test('取文字時不去重（同 Legado）', () {
    expect(rule().getStringList('class.kind@tag.span@text'), [
      '玄幻',
      '玄幻',
      '仙俠',
    ]);
  });
}
