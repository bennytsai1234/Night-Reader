import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/chinese/chinese_utils.dart';
import 'package:night_reader/core/chinese/rule_script.dart';
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

  /// 正文照顯示的寫法轉過，再套照同一個寫法轉過的規則。
  String shown(String raw, ReplaceRule rule, int convertType) => rule
      .inScript(convertType)
      .apply(
        const ChineseTextConverter().convert(raw, convertType: convertType),
      );

  group('正則的語法轉完和原本一樣，只轉漢字', () {
    test('\\p{…}、字元類別、跳脫字元與具名群組不動', () {
      final rule = ReplaceRule(
        pattern: r'(?<名>广告)\p{P}+[^\s\d]\\n\.\x{5E7F}[广告]{2}\k<名>(?<=说)',
      );
      expect(
        rule.inScript(_s2t).pattern,
        r'(?<名>廣告)\p{P}+[^\s\d]\\n\.\x{5E7F}[廣告]{2}\k<名>(?<=說)',
      );
    });

    test('「替換為」的 \$1、\${名稱}、跳脫字元不動，@js: 整段不動', () {
      expect(
        ReplaceRule(
          pattern: '(说)',
          replacement: r'$1说${名}\$',
        ).inScript(_s2t).replacement,
        r'$1說${名}\$',
      );
      const js = '@js:result.replace("说", "话")';
      expect(
        ReplaceRule(pattern: '说', replacement: js).inScript(_s2t).replacement,
        js,
      );
    });

    test('不轉繁簡時規則照原樣', () {
      final rule = ReplaceRule(pattern: '广告', replacement: '说');
      expect(rule.inScript(0), same(rule));
    });

    test('轉出來的規則存起來重用', () {
      final rule = ReplaceRule(pattern: '广告词', replacement: '');
      expect(
        identical(
          rule.inScript(_s2t).pattern,
          ReplaceRule(pattern: '广告词', replacement: '').inScript(_s2t).pattern,
        ),
        isTrue,
      );
    });
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
}
