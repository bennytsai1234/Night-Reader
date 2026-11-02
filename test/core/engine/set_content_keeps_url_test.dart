import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/analyze_rule.dart';

import '../../test_helper.dart';

/// `setContent(content, baseUrl)` 同 Legado `AnalyzeRule.setContent`：
/// 沒給網址就只換內容，原本的 baseUrl、redirectUrl 都留著。
void main() {
  setupTestDI();
  TestWidgetsFlutterBinding.ensureInitialized();
  final skip = quickJsUnavailableReason();

  AnalyzeRule page() {
    final rule = AnalyzeRule().setContent(
      '<i>舊</i>',
      baseUrl: 'https://page.test/c/1',
    )..setRedirectUrl('https://page.test/final/1');
    addTearDown(rule.dispose);
    return rule;
  }

  test('沒給網址：內容換掉，baseUrl 與 redirectUrl 不動', () {
    final rule = page()..setContent('<i>新</i>');

    expect(rule.getString('tag.i@text'), '新');
    expect(rule.baseUrl, 'https://page.test/c/1');
    expect(rule.redirectUrl, 'https://page.test/final/1');
  });

  test('有給網址：baseUrl 換成新的，redirectUrl 跟著（夜讀解析器靠這個補網址）', () {
    final rule = page()
      ..setContent('<i>新</i>', baseUrl: 'https://other.test/x');

    expect(rule.baseUrl, 'https://other.test/x');
    expect(rule.redirectUrl, 'https://other.test/x');
  });

  test('規則 JS 的 java.setContent(html) 沒給第二個參數：網址留著', () {
    final rule = page();

    expect(
      rule.evalJS(r'''
        java.setContent('<p>新</p>');
        [java.getString('tag.p@text'), baseUrl, redirectUrl].join('|')
      ''', null),
      '新|https://page.test/c/1|https://page.test/final/1',
    );
    expect(rule.baseUrl, 'https://page.test/c/1');
    expect(rule.redirectUrl, 'https://page.test/final/1');
  }, skip: skip);

  test('規則 JS 的 java.setContent(html, url) 有給：換成新網址', () {
    final rule = page();

    rule.evalJS("java.setContent('<p>新</p>', 'https://other.test/y'); 1", null);

    expect(rule.baseUrl, 'https://other.test/y');
  }, skip: skip);
}
