import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/parsers/analyze_by_xpath.dart';

/// XPath 規則照 Legado 用的 JsoupXpath。
void main() {
  // 思兔阅读的目錄 `//dd[a]`、第一版主 banzhu 的 `//a[@class]`：條件只寫
  // 子節點或屬性名稱，有就成立。
  group('只寫名稱的條件：有那個子節點或屬性就成立', () {
    const html = '''
      <dl id="allchapter">
        <dd><a href="/1.html">第一章</a></dd>
        <dd>分卷：開端</dd>
        <dd><a href="/2.html">第二章</a></dd>
      </dl>
      <li><div><a class="t" href="/b1">甲</a><a href="/b2">乙</a></div></li>
    ''';

    test('[a]：有 a 子節點', () {
      final xpath = AnalyzeByXPath(html);
      expect(xpath.getStringList("//*[@id='allchapter']//dd[a]/a/text()"), [
        '第一章',
        '第二章',
      ]);
      expect(xpath.getElements('//dd[a]'), hasLength(2));
    });

    test('[@class]：有 class 屬性', () {
      expect(AnalyzeByXPath(html).getStringList('//li/div//a[@class]/text()'), [
        '甲',
      ]);
    });

    test('[not(a)]、[not(@class)]：沒有才成立', () {
      final xpath = AnalyzeByXPath(html);
      expect(xpath.getStringList('//dd[not(a)]/text()'), ['分卷：開端']);
      expect(xpath.getStringList('//li//a[not(@class)]/text()'), ['乙']);
    });
  });
}
