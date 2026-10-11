import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/rule_analyzer.dart';

void main() {
  group('RuleAnalyzer.splitRule 切分書源規則的組合運算子', () {
    const operators = ['&&', '||', '%%'];

    test('沒有運算子時整條規則原樣回傳', () {
      final analyzer = RuleAnalyzer('class.title@text');

      expect(analyzer.splitRule(operators), ['class.title@text']);
    });

    test('依第一個出現的運算子切分，並記下運算子種類', () {
      final analyzer = RuleAnalyzer('tag.h1@text&&tag.h2@text&&tag.h3@text');

      expect(analyzer.splitRule(operators), [
        'tag.h1@text',
        'tag.h2@text',
        'tag.h3@text',
      ]);
      expect(analyzer.elementsType, '&&');
    });

    test('只以第一個運算子切分，後面不同種類的運算子留在片段內', () {
      final analyzer = RuleAnalyzer('a@text||b@text&&c@text');

      expect(analyzer.splitRule(operators), ['a@text', 'b@text&&c@text']);
      expect(analyzer.elementsType, '||');
    });

    test('方括號與圓括號內的運算子不切分', () {
      final analyzer = RuleAnalyzer(
        "//div[@class='a||b']/text()||//span[contains(text(),'x&&y')]/text()",
      );

      expect(analyzer.splitRule(operators), [
        "//div[@class='a||b']/text()",
        "//span[contains(text(),'x&&y')]/text()",
      ]);
    });

    test('括號不成對時放棄切分，回傳整條規則', () {
      const rule = '//div[@class=x||y';
      final analyzer = RuleAnalyzer(rule);

      expect(analyzer.splitRule(operators), [rule]);
    });

    test('單一分隔符依序切出每一段', () {
      final analyzer = RuleAnalyzer('class.list@tag.li@tag.a');

      expect(analyzer.splitRule(['@']), ['class.list', 'tag.li', 'tag.a']);
    });

    test('單一分隔符不切開方括號內的內容', () {
      final analyzer = RuleAnalyzer('[data-src=a@b.jpg]@attr.data-src');

      expect(analyzer.splitRule(['@']), [
        '[data-src=a@b.jpg]',
        'attr.data-src',
      ]);
    });

    test('程式碼模式下引號內的運算子不切分', () {
      final analyzer = RuleAnalyzer(
        r"$.list[?(@.tag=='a||b')].name||$.name",
        isCode: true,
      );

      expect(analyzer.splitRule(['&&', '||']), [
        r"$.list[?(@.tag=='a||b')].name",
        r'$.name',
      ]);
    });
  });

  group('RuleAnalyzer.innerRule 替換內嵌規則', () {
    test(r'把每個 {$.xxx} 換成查詢結果', () {
      final analyzer = RuleAnalyzer(
        r'/book/{$.id}/chapter/{$.cid}.html',
        isCode: true,
      );
      final values = {r'$.id': '42', r'$.cid': '7'};

      final result = analyzer.innerRule(r'{$.', fr: (it) => values[it]);

      expect(result, '/book/42/chapter/7.html');
    });

    test('內嵌規則內有成對大括號時取到完整內容', () {
      final analyzer = RuleAnalyzer(r'x={$.a[?(@.b=={1})]}', isCode: true);
      String? captured;

      analyzer.innerRule(
        r'{$.',
        fr: (it) {
          captured = it;
          return 'v';
        },
      );

      expect(captured, r'$.a[?(@.b=={1})]');
    });

    test('查詢結果為空時保留原本的片段', () {
      const rule = r'/book/{$.missing}.html';
      final analyzer = RuleAnalyzer(rule, isCode: true);

      expect(analyzer.innerRule(r'{$.', fr: (_) => null), rule);
      analyzer.reSetPos();
      expect(analyzer.innerRule(r'{$.', fr: (_) => ''), rule);
    });

    test('沒有內嵌規則時原樣回傳', () {
      const rule = r'$.data.list';
      final analyzer = RuleAnalyzer(rule, isCode: true);

      expect(analyzer.innerRule(r'{$.', fr: (_) => 'unused'), rule);
    });
  });

  group('RuleAnalyzer.innerRuleRange 替換起訖標記之間的內容', () {
    test('每段標記之間的內容換成回傳值', () {
      final analyzer = RuleAnalyzer('a{{1+1}}b{{2+2}}c');

      final result = analyzer.innerRuleRange('{{', '}}', fr: (it) => '[$it]');

      expect(result, 'a[1+1]b[2+2]c');
    });

    test('回傳 null 時該段換成空字串', () {
      final analyzer = RuleAnalyzer('a{{x}}b');

      expect(analyzer.innerRuleRange('{{', '}}', fr: (_) => null), 'ab');
    });
  });
}
