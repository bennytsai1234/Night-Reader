import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/analyze_rule.dart';
import 'package:night_reader/core/models/book_source.dart';

import '../../test_helper.dart';

/// 規則 JS 裡有 `{{ }}` 時（夜讀算「動態規則」），JS 交回空的就是空的，同
/// Legado；不拿 JS 程式碼當結果。Lofter 的目錄網址規則兩個條件都不成立時
/// 沒有值，原本送出去的網址是那段程式碼。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupTestDI();

  AnalyzeRule rule() =>
      AnalyzeRule(source: BookSource(bookSourceUrl: 'https://l.test'))
          .setContent('{"grain":{"id":3}}', baseUrl: 'https://l.test/detail');

  const lofter =
      r'$.response.blogsetting.blogId'
      '\n@js:\nif(result){\n'
      r"id='{{$.response.blogsetting.blogId}}';"
      '\nresult="u"+id}';

  test('JS 沒有值時是空的，不是程式碼', () {
    expect(rule().getString(lofter), '');
    expect(rule().getElements(r'@js:""'), isEmpty);
  });

  test('目錄網址沒有值時照舊用回目前的網址', () {
    expect(rule().getString(lofter, isUrl: true), 'https://l.test/detail');
  });

  test('JS 有值時照舊', () {
    expect(
      rule().getString(r'$.grain.id@js:"n" + result + "{{$.grain.id}}"'),
      'n33',
    );
  });
}
