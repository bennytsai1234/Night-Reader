import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/chinese/chinese_utils.dart';
import 'package:night_reader/core/chinese/replace_rule_script.dart';
import 'package:night_reader/core/engine/reader/chinese_text_converter.dart';
import 'package:night_reader/core/models/replace_rule.dart';

const int _s2t = 1;
const int _t2s = 2;

void main() {
  setUpAll(() {
    ChineseUtils.initializeFromDictionaryData([
      for (final path in ChineseUtils.dictionaryAssetPaths)
        File(path).readAsStringSync(),
    ]);
  });

  /// 正文照顯示的寫法轉過，再依序套這條規則的每種寫法（同閱讀器）。
  String shown(String raw, ReplaceRule rule, int convertType) => rule
      .matchVariants([convertType])
      .fold(
        const ChineseTextConverter().convert(raw, convertType: convertType),
        (text, variant) => variant.apply(text),
      );

  group('正則的語法轉完和原本一樣，只轉漢字', () {
    test('\\p{…}、字元類別、跳脫字元與具名群組不動', () {
      final rule = ReplaceRule(
        pattern: r'(?<名>广告)\p{P}+[^\s\d]\\n\.\x{5E7F}[广告]{2}\k<名>(?<=说)',
      );
      expect(
        rule.matchVariants([_s2t]).last.pattern,
        r'(?<名>廣告)\p{P}+[^\s\d]\\n\.\x{5E7F}[廣告]{2}\k<名>(?<=說)',
      );
    });

    test('先比字面，再比轉過的；替換成的字照字面放（同 Legado）', () {
      final variants = ReplaceRule(
        pattern: '(说)',
        replacement: r'$1说',
      ).matchVariants([_s2t]);
      expect([for (final rule in variants) rule.pattern], ['(说)', '(說)']);
      expect([for (final rule in variants) rule.replacement], [r'$1说', r'$1说']);
    });

    test('不轉繁簡、或轉完和字面一樣時只比一次', () {
      final rule = ReplaceRule(pattern: '广告', replacement: '说');
      expect(rule.matchVariants([0]), [same(rule)]);
      expect(ReplaceRule(pattern: 'ad').matchVariants([_s2t]), hasLength(1));
    });

    test('轉出來的規則字存起來重用', () {
      String converted() => ReplaceRule(
        pattern: '广告词',
        replacement: '',
      ).matchVariants([_s2t]).last.pattern;
      expect(identical(converted(), converted()), isTrue);
    });
  });

  // 轉換器轉兩次不一定一樣（干擾→幹擾、襯托→襯託）：照畫面寫的規則靠字面
  // 那次對上，不會被轉壞。
  group('照畫面寫的規則，字面就對得到', () {
    for (final (pattern, raw) in [
      ('干擾', '干扰'),
      ('襯托', '衬托'),
      ('幾里', '几里'),
      ('征討', '征讨'),
      ('斗膽', '斗胆'),
    ]) {
      test('規則「$pattern」、正文「$raw」', () {
        final rule = ReplaceRule(pattern: pattern, isRegex: false);
        expect(shown('前$raw後', rule, _s2t), '前後');
      });
    }
  });

  group('簡體寫的規則與繁體寫的規則，對同一份正文都對得到', () {
    for (final pattern in ['头发', '頭髮']) {
      test('簡轉繁：規則寫「$pattern」', () {
        final rule = ReplaceRule(pattern: pattern, isRegex: false);
        expect(shown('她的头发很长', rule, _s2t), '她的很長');
      });
      test('繁轉簡：規則寫「$pattern」', () {
        final rule = ReplaceRule(pattern: pattern, isRegex: false);
        expect(shown('她的頭髮很長', rule, _t2s), '她的很长');
      });
    }
  });

  // 一個簡體字對到好幾個繁體字（发→發／髮、干→乾／幹、面→面／麵、后→後／后、
  // 里→裡／里）：詞組照詞組轉，規則與正文轉出同一個字就對得到；規則只寫單
  // 一個字時沒有上下文，照單字的預設轉，和正文的詞組不同時對不到。
  group('一對多的字：規則與正文用同一個轉換器', () {
    final cases = <(String, String, bool)>[
      ('头发', '她的头发很长', true),
      ('发现', '他发现了', true),
      ('干净', '房间很干净', true),
      ('干部', '他是干部', true),
      ('面条', '一碗面条', true),
      ('后来', '后来他走了', true),
      ('皇后', '皇后来了', true),
      ('这里', '就在这里', true),
      ('公里', '三公里', true),
      ('发', '她的头发很长', false),
      ('面', '一碗面条', false),
    ];

    test('正則被語法隔開的字各自轉：(头)发 對不到「头发」', () {
      final rule = ReplaceRule(pattern: r'(头)发', replacement: r'$1');
      expect(shown('她的头发很长', rule, _s2t), '她的頭髮很長');
    });
    for (final (pattern, raw, matches) in cases) {
      test('規則「$pattern」、正文「$raw」：${matches ? '對得到' : '對不到'}', () {
        final rule = ReplaceRule(pattern: pattern, isRegex: false);
        final result = shown(raw, rule, _s2t);
        final converted = const ChineseTextConverter().convert(
          raw,
          convertType: _s2t,
        );
        expect(result != converted, matches);
      });
    }
  });

  group('兩種寫法對同一段字比，每一處只換一次', () {
    String applied(String text, ReplaceRule rule, List<int> types) =>
        rule.applyMatchingVariants(text, types);

    test('換上的字含有轉過的寫法時不再換一次', () {
      final rule = ReplaceRule(pattern: '小说|小說', replacement: '網路小說');
      expect(applied('我愛看小說。', rule, [_s2t]), '我愛看網路小說。');
    });

    test('兩種寫法對到重疊的字時照字面那一種換', () {
      // 字面「广告词」對不到，轉過的「廣告詞」與字面的「告詞」重疊。
      final rule = ReplaceRule(pattern: '告詞|广告词', replacement: r'[$0]');
      expect(applied('廣告詞', rule, [_s2t]), '廣[告詞]');
    });

    test('兩種寫法各自對到不同的地方，都換', () {
      final rule = ReplaceRule(pattern: '广告', replacement: '', isRegex: false);
      expect(rule.applyMatchingVariants('广告與廣告', [_s2t]), '與');
    });

    test('長度是零的對法（行首）在同一處只插一次', () {
      // 字面與轉過的（[說說]）都在兩行的行首對到。
      final rule = ReplaceRule(pattern: '(?m)^(?=[说說])', replacement: '>');
      expect(applied('說話\n说话', rule, [_s2t]), '>說話\n>说话');
    });

    test('不轉繁簡時和一條規則套一次一樣', () {
      final rule = ReplaceRule(pattern: '小说|小說', replacement: '網路小說');
      expect(applied('小说', rule, [0]), rule.apply('小说'));
    });
  });
}
