import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/analyze_rule.dart';

import '../../test_helper.dart';

/// 規則的模式照 Legado 的 `AnalyzeRule.SourceRule` 決定。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupTestDI();

  String read(dynamic content, String rule, {Map<String, String>? vars}) {
    final analyzer = AnalyzeRule().setContent(content);
    vars?.forEach(analyzer.put);
    try {
      return analyzer.getString(rule);
    } finally {
      analyzer.dispose();
    }
  }

  group('JSON 內容', () {
    const json = '{"title":"第一章","links":{"reader":"/c/1"},"第一章":"錯誤"}';

    test('沒有前綴的規則是 JSON 路徑', () {
      expect(read(json, 'img@alt||text||title'), '第一章');
      expect(read(json, 'links.reader'), '/c/1');
    });

    test('前綴照樣指定模式', () {
      expect(read('{"p":"<b>粗</b>"}', '@CSS:b@text'), '粗');
      expect(read('{"p":"<b>粗</b>"}', r'@Json:$.p'), '<b>粗</b>');
    });

    // 組好的文字剛好是另一個欄位名時，不再拿去查一次。
    test('含 {{ }}、@get:、{\$.x} 的規則組好就是文字', () {
      expect(read(json, r'{$.title}'), '第一章');
      expect(read(json, r'{{$.title}}'), '第一章');
      expect(read(json, '@get:{chosen}', vars: {'chosen': '第一章'}), '第一章');
      expect(read(json, r'第{$.title}回'), '第第一章回');
    });
  });

  // Legado `splitSourceRule(ruleStr, allInOne = true)`：getElement、getElements
  // 的規則第一個字是 `:` 時去掉冒號、整段是正則；正則照 Java `Pattern` 的
  // 預設，`.` 不跨行、`^`／`$` 不逐行，寫了 `(?s)`、`(?m)` 才開。
  group('冒號開頭的整份內容正則', () {
    List<dynamic> elements(dynamic content, String rule) {
      final analyzer = AnalyzeRule().setContent(content);
      try {
        return analyzer.getElements(rule);
      } finally {
        analyzer.dispose();
      }
    }

    dynamic element(dynamic content, String rule) {
      final analyzer = AnalyzeRule().setContent(content);
      try {
        return analyzer.getElement(rule);
      } finally {
        analyzer.dispose();
      }
    }

    test('getElements 取出每一筆的分組', () {
      expect(elements('第1章\n第2章', r':第(\d+)章'), [
        ['第1章', '1'],
        ['第2章', '2'],
      ]);
    });

    test('getElement 交回第一筆的分組', () {
      expect(element('書名：西遊記\n作者：吳承恩', r':書名：(.+)\n作者：(.+)'), [
        '書名：西遊記\n作者：吳承恩',
        '西遊記',
        '吳承恩',
      ]);
    });

    test('沒寫 (?s) 時 . 不跨行', () {
      expect(elements('第一章\n第二章', ':(?=第)第.*章'), [
        ['第一章'],
        ['第二章'],
      ]);
      expect(elements('第一章\n第二章', ':(?s)第一.*第二'), [
        ['第一章\n第二'],
      ]);
      expect(elements('第一章\n第二章', ':第一.*第二'), isEmpty);
    });

    test('沒寫 (?m) 時 ^ 只對整段開頭', () {
      expect(elements('第一章\n第二章', ':^第二章'), isEmpty);
      expect(elements('第一章\n第二章', ':(?m)^第二章'), [
        ['第二章'],
      ]);
    });

    // 同 Legado：getString 的規則沒有「整份內容正則」，冒號開頭照網頁選擇器讀。
    test(r'$ 對得到最後一個換行之前，開頭的旗標可以連寫', () {
      expect(elements('第1章\n', r':第(\d+)章$'), [
        ['第1章', '1'],
      ]);
      expect(elements('A\nB', ':(?i)(?s)a.b'), [
        ['A\nB'],
      ]);
      expect(elements('ab', ':(?x)a b'), [
        ['ab'],
      ]);
    });

    test('getString 不把冒號開頭當正則', () {
      expect(read('<p>內文</p>', r':(?<=p>)[^<]+##文##字'), isNot('內字'));
    });
  });

  test('## 之後的正則認得 (?x)', () {
    expect(read('<p>ab</p>', 'p@text##(?x)a b##X'), 'X');
  });

  test('## 之後的正則認得開頭的 (?s)', () {
    expect(read('<p>第一行\n第二行</p>', r'p@html##(?s)第一.*第二##合併'), '<p>合併行</p>');
  });

  // Legado 對規則 JS 交來的 JS 物件直接讀鍵，不管外層內容是什麼。
  group('規則 JS 交來的物件', () {
    test('外層是網頁時也讀得到欄位', () {
      expect(
        read('<p>外層網頁</p>', '@js:java.getString("title", {title:"第一章"})'),
        '第一章',
      );
      expect(
        read(
          '<p>外層網頁</p>',
          '@js:java.getStringList("titles", {titles:["第一章","第二章"]})'
              '.join("|")',
        ),
        '第一章|第二章',
      );
    });
  });
}
