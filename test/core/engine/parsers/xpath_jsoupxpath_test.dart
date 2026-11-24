import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/parsers/analyze_by_xpath.dart';

/// XPath 規則照 Legado 用的 JsoupXpath 2.5.3：函式、軸與運算子逐一對過
/// （`org.seimicrawler.xpath.core` 的 function、axis、node 與 Xpath.g4）。
void main() {
  const html = '''
<div id="list">
  <h2 class="t">書名：斗羅大陸</h2>
  <ul class="toc">
    <li class="c a"><a href="/1.html" title="一">第1章 開始</a><span>2024-01-02</span></li>
    <li class="c"><a href="/2.html" title="二">第2章 風起</a><span>共 1234 字</span></li>
    <li class="v"><a href="/3.html" title="三">第3章 雲湧</a></li>
  </ul>
</div>
''';
  List<String> list(String rule) => AnalyzeByXPath(html).getStringList(rule);

  group('條件裡的函式', () {
    test('position()、last()、first()、[-1]', () {
      expect(list('//li[position()=2]/a/text()'), ['第2章 風起']);
      expect(list('//li[position()>=2]/a/text()'), ['第2章 風起', '第3章 雲湧']);
      expect(list('//li[last()-1]/a/text()'), ['第2章 風起']);
      expect(list('//li[first()]/a/text()'), ['第1章 開始']);
      expect(list('//li[-1]/a/text()'), ['第3章 雲湧']);
    });

    test('count()、string-length()、contains()、starts-with()、not()', () {
      expect(list('//ul[count(li)=3]/@class'), ['toc']);
      expect(list('//ul[count(li)=2]/@class'), isEmpty);
      expect(list('//a[string-length(@title)=1][1]/@href'), [
        '/1.html',
        '/2.html',
        '/3.html',
      ]);
      expect(list("//li[contains(@class,'a')]/a/text()"), ['第1章 開始']);
      expect(list("//a[starts-with(@title,'二')]/text()"), ['第2章 風起']);
      expect(list("//li[not(contains(@class,'c'))]/a/text()"), ['第3章 雲湧']);
    });

    test('四則運算', () {
      expect(list('//li[position()=1+1]/a/text()'), ['第2章 風起']);
      expect(list('//li[position()=4 div 2]/a/text()'), ['第2章 風起']);
      expect(list('//li[position() mod 2=1]/a/text()'), ['第1章 開始', '第3章 雲湧']);
    });

    test('and 接只寫名稱的條件', () {
      expect(list("//li[@class='c' and a]/a/text()"), ['第2章 風起']);
      expect(list("//li[@class='v' or @class='c']/a/text()"), [
        '第2章 風起',
        '第3章 雲湧',
      ]);
    });
  });

  group('JsoupXpath 的運算子', () {
    test('^= \$= *= 是開頭、結尾、含', () {
      expect(list("//li[@class^='c']/a/text()"), ['第1章 開始', '第2章 風起']);
      expect(list(r"//li[@class$='a']/a/text()"), ['第1章 開始']);
      expect(list("//li[@class*=' a']/a/text()"), ['第1章 開始']);
    });

    test('~= 整段符合正則、!~ 整段不符合', () {
      expect(list(r"//a[@href~='/[12]\.html']/text()"), ['第1章 開始', '第2章 風起']);
      expect(list(r"//a[@href!~'/[12]\.html']/text()"), ['第3章 雲湧']);
      // 整段：只符合一部分不算（Java String.matches）。
      expect(list("//a[@href~='[12]']/text()"), isEmpty);
    });
  });

  group('最後一步是函式', () {
    test('num() 取第一個數字', () {
      expect(list('//li[2]/span/num()'), ['1234']);
    });

    test('substring 一族', () {
      expect(list('//h2/substring(text(),3)'), ['：斗羅大陸']);
      expect(list('//h2/substring(text(),1,2)'), ['書名']);
      expect(list('//h2/substring-ex(text(),0,2)'), ['書名']);
      expect(list("//h2/substring-after(text(),'：')"), ['斗羅大陸']);
      expect(list("//h2/substring-before(text(),'：')"), ['書名']);
      expect(list("//li[1]/a/substring-after-last(@href,'/')"), ['1.html']);
      expect(list("//li[1]/a/substring-before-last(@href,'.')"), ['/1']);
    });

    test('整段是 concat()、sum()', () {
      expect(list("concat(//h2/text(),'!')"), ['書名：斗羅大陸!']);
      expect(list('sum(//li/span/num())'), ['3258']);
    });
  });

  group('軸', () {
    test('..、parent::、ancestor::', () {
      expect(list('//li[1]/a/../@class'), ['c a']);
      expect(list('//li[1]/a/parent::li/@class'), ['c a']);
      expect(list('//li[1]/a/ancestor::div/@id'), ['list']);
    });

    test('following-sibling-one::、preceding-sibling-one::', () {
      expect(list('//li[1]/following-sibling-one::li/a/text()'), ['第2章 風起']);
      expect(list('//li[3]/preceding-sibling-one::li/a/text()'), ['第2章 風起']);
    });

    test('preceding:: 是自己與祖先前面的兄弟', () {
      expect(list('//li[3]/preceding::li/a/text()'), ['第2章 風起', '第1章 開始']);
      expect(list('//ul/preceding::h2/text()'), ['書名：斗羅大陸']);
    });

    test('attribute::', () {
      expect(list('//li[1]/a/attribute::title'), ['一']);
    });
  });

  test('不支援的函式明確報錯，不當成路徑一直找下去', () {
    expect(
      () =>
          AnalyzeByXPath(html)
              .getStringList("//li[1]/span/format-date(text(),'yyyy')"),
      throwsA(anything),
    );
  });
}
