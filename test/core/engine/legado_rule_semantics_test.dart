import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/analyze_rule.dart';
import 'package:night_reader/core/engine/rule_analyzer.dart';
import 'package:night_reader/core/models/source/book_source.dart';

import '../../test_helper.dart';

/// 規則的取字、組合、取代與 `@put` 照 Legado `AnalyzeRule`、`RuleAnalyzer`。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupTestDI();

  AnalyzeRule rule(dynamic content) =>
      AnalyzeRule(source: BookSource(bookSourceUrl: 'https://site.test'))
          .setContent(content, baseUrl: 'https://site.test/book/1');

  group('XPath', () {
    test('空的屬性值後面接別的屬性，照原樣讀得到', () {
      expect(
        rule('<html><body><div id="" class="content">正文</div></body></html>')
            .getString("@XPath://div[@class='content']/text()"),
        '正文',
      );
      expect(
        rule(
          '<html><body><a data-note="" href="/chapter/1">一</a></body></html>',
        ).getString('@XPath://a/@href'),
        '/chapter/1',
      );
    });
  });

  group('JSON 的 getElement', () {
    test('對到陣列時交出整個陣列，後面的規則照索引取', () {
      final r = rule('{"data":[{"name":"甲書"},{"name":"乙書"}]}');
      final data = r.getElement(r'$.data');
      expect(data, isA<List>());
      expect((data as List).length, 2);
      expect(r.setContent(data).getString(r'$[1].name'), '乙書');
    });

    test('對到物件時照舊是那個物件', () {
      final r = rule('{"data":{"name":"甲書"}}');
      expect(r.setContent(r.getElement(r'$.data')).getString('name'), '甲書');
    });
  });

  group('組合規則', () {
    test('第一個分隔符後面的括號裡有同一個符號時不切開', () {
      expect(RuleAnalyzer(r"$.missing||$['a||b']").splitRule(['&&', '||']), [
        r'$.missing',
        r"$['a||b']",
      ]);
      expect(
        RuleAnalyzer(r'$.name||$.list[?(@.a||@.b)].x||$.c')
            .splitRule(['&&', '||']),
        [r'$.name', r'$.list[?(@.a||@.b)].x', r'$.c'],
      );
      expect(
        rule('{"a||b":"第一章"}').getString(r"@json:$.missing||$['a||b']"),
        '第一章',
      );
    });

    test('沒有括號時照舊切', () {
      expect(RuleAnalyzer('a||b||c').splitRule(['&&', '||']), ['a', 'b', 'c']);
    });
  });

  group('##正則##取代 照 Java 展開', () {
    const ten = r'##(a)(b)(c)(d)(e)(f)(g)(h)(i)(j)##$10';
    test(r'$10 是第十組', () {
      final r = rule('<p>abcdefghij</p>');
      expect(r.getString('@css:p@text$ten'), 'j');
      expect(r.getString('@css:p@text$ten###'), 'j');
      expect(r.getStringList('@css:p@text$ten'), ['j']);
    });

    test(r'分組裡的 $2 照原樣放', () {
      expect(
        rule(r'<p>x$2y</p>').getString(r'@css:p@text##(x.*)(y)##[$1]'),
        r'[x$2]',
      );
    });

    test(r'\$ 是字面的 $', () {
      expect(rule('<p>12</p>').getString(r'@css:p@text##(\d+)##\$$1'), r'$12');
    });
  });

  group('只有 ##取代 的清單規則', () {
    test('拿目前的內容去取代，照換行切成一筆筆', () {
      expect(rule('01\n02').getStringList('##0##章'), ['章1', '章2']);
    });
  });

  group('@put', () {
    test('取到空的也存，蓋掉上一次存的', () {
      final r = rule('<p>第二章</p>');
      r.put('titleSuffix', '第一章');
      expect(
        r.getString('@put:{"titleSuffix":"@css:.suffix@text"}@css:p@text'),
        '第二章',
      );
      expect(r.get('titleSuffix'), '');
    });
  });
}
