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
  // novelnext 這類英文小說站：搜尋結果每一列用 `@XPath:div[2]/div/h3/a/@title`
  // 從那一列往下找（JsoupXpath 從 JXNode 起算）。
  group('相對路徑：從目前的元素往下找', () {
    const html = '''
      <div class="list">
        <div class="row"><div>封面</div>
          <div><div><h3><a href="/a" title="Book A">A</a></h3>
          <span>x</span><span>Author A</span></div></div></div>
        <div class="row"><div>封面</div>
          <div><div><h3><a href="/b" title="Book B">B</a></h3>
          <span>x</span><span>Author B</span></div></div></div>
      </div>
    ''';

    test('列表的每一項各自從自己往下找', () {
      final rows = AnalyzeByXPath(html).getElements("//div[@class='row']");
      expect(rows, hasLength(2));
      final second = AnalyzeByXPath(rows[1]);
      expect(second.getStringList('div[2]/div/h3/a/@title'), ['Book B']);
      expect(second.getString('div[2]/div/span[2]/text()'), 'Author B');
      expect(second.getStringList('div[2]/div/h3/a/@href'), ['/b']);
      // 開頭是 / 的照舊從整份（這一列）找。
      expect(second.getStringList('//h3/a/text()'), ['B']);
    });

    test('表格的一列也從那一列往下找', () {
      const table =
          '<table><tr class="r"><td>甲書</td><td><a href="/a">作者甲</a></td></tr>'
          '<tr class="r"><td>乙書</td><td><a href="/b">作者乙</a></td></tr></table>';
      final rows = AnalyzeByXPath(table).getElements("//tr[@class='r']");
      expect(rows, hasLength(2));
      final second = AnalyzeByXPath(rows[1]);
      expect(second.getString('td[1]/text()'), '乙書');
      expect(second.getStringList('td[2]/a/@href'), ['/b']);
    });

    test('| 兩邊各從自己的起點找', () {
      final rows = AnalyzeByXPath(html).getElements("//div[@class='row']");
      final first = AnalyzeByXPath(rows[0]);
      expect(first.getStringList('div[2]/div/h3/a/@title | //span[2]/text()'), [
        'Book A',
        'Author A',
      ]);
    });

    test('只有第一步可以省略 /', () {
      final rows = AnalyzeByXPath(html).getElements("//div[@class='row']");
      final first = AnalyzeByXPath(rows[0]);
      // 中間少了 / 的不是合法的路徑，照舊當成錯誤，不默默當成 div/div。
      expect(() => first.getStringList('div[2] div'), throwsFormatException);
    });

    test('整份網頁時從 <html> 往下找', () {
      // JsoupXpath 整份網頁的起點是 doc.children()，也就是 <html>。
      expect(AnalyzeByXPath(html).getStringList('body/div/@class'), ['list']);
    });
  });

  // 轻文库小说（app.wenku8.com）回的是 XML：`<page/>` 自己結束，書是
  // `<item>`，搜尋規則是 `@XPath:item`、`//data[@name='Title']/text()`。
  group('XML 照 Legado 用 XML 解析器讀', () {
    const xml = '''<?xml version="1.0" encoding="utf-8"?>
<result>
<page num='1'/>
<item aid='1973'><data name='Title'><![CDATA[魔法师甲]]></data><data name='Author' value='作者甲'/></item>
<item aid='2088'><data name='Title'><![CDATA[魔法师乙]]></data><data name='Author' value='作者乙'/></item>
</result>''';

    test('相對路徑從根元素往下找，自己結束的標籤不會包住後面的', () {
      final items = AnalyzeByXPath(xml).getElements('item');
      expect(items, hasLength(2));
      final second = AnalyzeByXPath(items[1]);
      expect(second.getString("//data[@name='Title']/text()"), '魔法师乙');
      expect(second.getString("//data[@name='Author']/@value"), '作者乙');
      expect(second.getString('//@aid'), '2088');
    });

    test('標籤名稱照原文，title 這類網頁標籤不被搬走', () {
      const doc = '''<?xml version="1.0"?>
<Package><title>書名</title><Chapter id="1"/><Chapter id="2"/></Package>''';
      final xpath = AnalyzeByXPath(doc);
      expect(xpath.getStringList('title/text()'), ['書名']);
      expect(xpath.getStringList('//Chapter/@id'), ['1', '2']);
    });

    test('text()[n] 取每個元素底下第 n 段文字', () {
      const page = '<div><p class="m">作者：甲<br>分類：玄幻</p></div>';
      final xpath = AnalyzeByXPath(page);
      expect(xpath.getString("//p[@class='m']/text()[2]"), '分類：玄幻');
      expect(xpath.getString("//p[@class='m']/text()[1]"), '作者：甲');
    });

    test('寫壞的 XML 照網頁讀', () {
      const broken = '<?xml version="1.0"?><a><b>x</a>';
      expect(AnalyzeByXPath(broken).getStringList('//b/text()'), ['x']);
    });
  });
}
