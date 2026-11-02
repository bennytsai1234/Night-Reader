import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/analyze_rule.dart';

import '../../test_helper.dart';

/// 只有空白的規則：Legado 拆出來的規則清單是空的，
/// `getString` 回空字串、`getStringList` 回沒有、`getElement` 回 null、
/// `getElements` 回空清單；不是把整份內容當結果。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupTestDI();

  const html = '<div><p>甲</p><p>乙</p></div>';
  const json = '{"a":"值","list":[1,2]}';

  AnalyzeRule at(String content) {
    final rule = AnalyzeRule().setContent(
      content,
      baseUrl: 'https://l.test/book/',
    );
    addTearDown(rule.dispose);
    return rule;
  }

  for (final blank in [' ', '   ', '\n', '\t \n']) {
    final shown = blank.replaceAll('\n', r'\n').replaceAll('\t', r'\t');

    test('"$shown" 在網頁內容上沒有結果', () {
      final rule = at(html);

      expect(rule.getString(blank), '');
      expect(rule.getString(blank, mContent: '別的內容'), '');
      expect(rule.getStringList(blank), isEmpty);
      expect(rule.getElement(blank), isNull);
      expect(rule.getElements(blank), isEmpty);
    });

    test('"$shown" 在 JSON 內容上沒有結果', () {
      final rule = at(json);

      expect(rule.getString(blank), '');
      expect(rule.getStringList(blank), isEmpty);
      expect(rule.getElement(blank), isNull);
      expect(rule.getElements(blank), isEmpty);
    });
  }

  test('網址規則只有空白：同 Legado，退回請求的網址', () {
    final rule = at(html);

    expect(rule.getString(' ', isUrl: true), 'https://l.test/book/');
    expect(rule.getStringList(' ', isUrl: true), isEmpty);
  });

  test('空字串規則照舊：沒有規則，沒有結果', () {
    final rule = at(html);

    expect(rule.getString(''), '');
    expect(rule.getStringList(''), isEmpty);
    expect(rule.getElement(''), isNull);
    expect(rule.getElements(''), isEmpty);
  });

  test('有內容的規則不受影響', () {
    final rule = at(html);

    expect(rule.getString('tag.p@text'), '甲\n乙');
    expect(rule.getStringList('tag.p@text'), ['甲', '乙']);
    expect(rule.getElements('tag.p'), hasLength(2));
    expect(rule.getString('@js:result.length > 0 ? "有" : "無"'), '有');
  });
}
