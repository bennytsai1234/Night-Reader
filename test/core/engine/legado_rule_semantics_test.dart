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

  group('java.setContent 交 Jsoup 節點', () {
    final skip = quickJsUnavailableReason();

    AnalyzeRule page() {
      final r = AnalyzeRule(
        source: BookSource(bookSourceUrl: 'https://site.test'),
      ).setContent('<p>舊</p>', baseUrl: 'https://site.test/old/1');
      addTearDown(r.dispose);
      return r;
    }

    test('同一條規則後面的 CSS @abs: 用那份文件的網址', () {
      expect(
        page().evalJS('''
          java.setContent(org.jsoup.Jsoup.parse('<a href="1.html">一</a>',
            'https://site.test/chapter/'));
          java.getString('@css:a@abs:href')
        ''', null),
        'https://site.test/chapter/1.html',
      );
    }, skip: skip);

    test('下一條規則的 CSS @abs: 還是那份文件的網址', () {
      final r = page();
      r.evalJS(
        "java.setContent(org.jsoup.Jsoup.parse('<a href=\"1.html\">一</a>', "
        "'https://site.test/chapter/')); 1",
        null,
      );
      expect(
        r.getString('@css:a@abs:href'),
        'https://site.test/chapter/1.html',
      );
    }, skip: skip);

    test('元素的 baseUri()、文件的 location() 讀同一份網址', () {
      final r = page();
      r.evalJS(
        "java.setContent(org.jsoup.Jsoup.parse('<a href=\"1.html\">一</a>', "
        "'https://site.test/chapter/')); 1",
        null,
      );
      expect(
        r.evalJS("java.getElement('a').first().baseUri()", null),
        'https://site.test/chapter/',
      );
      expect(
        r.evalJS(
          "java.getElement('html').first().ownerDocument().location()",
          null,
        ),
        'https://site.test/chapter/',
      );
    }, skip: skip);
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

  group('審查補的', () {
    test('最後一頁沒有下一頁連結時，組字的網址清單是空的', () {
      expect(
        rule('<p>沒有下一頁</p>').getStringList('{{@css:a.next@href}}', isUrl: true),
        isEmpty,
      );
    });

    test('JSON 不確定的路徑（[*]、..）不管幾筆都是清單，值是陣列也不展開', () {
      final one = rule('{"books":[{"name":"A"}]}');
      expect(one.getElement(r'$.books[*].name'), ['A']);
      final none = rule('{"books":[]}');
      expect(none.getElement(r'$.books[*].name'), isEmpty);
      final groups = rule('{"groups":[[{"t":"一"},{"t":"二"}]]}');
      expect(groups.getElements(r'$.groups[*]'), hasLength(1));
      expect(groups.getElements(r'$.groups[0]'), hasLength(2));
    });

    test('### 先截出片段再在片段上換：前後文的條件對不到就照原樣', () {
      expect(
        rule('<p>Author: Alice</p>')
            .getString(r'@css:p@text##(?<=Author: )(\w+)##[$1]###'),
        'Alice',
      );
    });

    test('上一段沒有結果時，這一段的 @put 照樣先存', () {
      final r = rule('<p>甲</p>');
      r.getString('<js>null</js>@put:{"k":"@css:p@text"}@css:p@text');
      expect(r.get('k'), '甲');
    });
  });
}
