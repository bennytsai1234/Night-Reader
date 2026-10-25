import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/analyze_rule.dart';

import '../../../test_helper.dart';

/// 規則的 @text、@ownText 和 Legado（Jsoup）一樣：區塊之間與 <br> 處留一個
/// 空格，<script> 的內容不算；:contains 不分大小寫。
void main() {
  setupTestDI();

  const html = '''
<div class="author">作者：<br>張三</div>
<div class="intro"><p>第一段</p><p>第二段</p><script>var x = 1;</script></div>
<ul><li>Alpha</li><li>beta</li></ul>
''';

  AnalyzeRule rule() =>
      AnalyzeRule()..setContent(html, baseUrl: 'https://site.test/');

  test('text keeps a space between blocks and at br', () {
    expect(rule().getString('.author@text'), '作者： 張三');
    expect(rule().getString('.intro@text'), '第一段 第二段');
    expect(rule().getString('.author@ownText'), '作者： 張三');
  });

  test(':contains ignores case like Jsoup', () {
    expect(rule().getString('li:contains(ALPHA)@text'), 'Alpha');
    expect(rule().getString('li:matches(^b)@text'), 'beta');
  });

  test('@css: select includes the starting element like Jsoup', () {
    final box = AnalyzeRule()
      ..setContent('<div class="box"><a href="/1">一</a></div>');
    final element = box.getElements('@css:.box').single;
    final item = AnalyzeRule()..setContent(element);
    expect(item.getString('@css:.box:contains(一)@class'), 'box');
    expect(item.getString('@css:a@href'), '/1');
  });
}
