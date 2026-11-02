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
