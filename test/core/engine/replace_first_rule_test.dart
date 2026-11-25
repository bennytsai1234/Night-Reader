import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/analyze_rule.dart';
import 'package:night_reader/core/models/source/book_source.dart';

import '../../test_helper.dart';

/// `規則##正則##取代###`：Legado 找第一個對到的、只交出它換過的樣子，對不到
/// 是空字串（`AnalyzeRule.replaceRegex` 的 replaceFirst），不管前面的選擇器
/// 是不是空的。正則寫壞時 `###` 交出取代式、`##` 改用純文字取代。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupTestDI();

  AnalyzeRule rule(dynamic content) =>
      AnalyzeRule(source: BookSource(bookSourceUrl: 'https://q.test'))
          .setContent(content, baseUrl: 'https://q.test/book/1');

  const html =
      '<p class="info">類別：玄幻 作者：張三 狀態：連載</p>'
      '<a class="read" href="/book/123/">開始閱讀</a>';

  test('### 只交出第一個對到的那段換過的樣子', () {
    expect(rule(html).getString(r'class.info@text##作者：(\S+)##$1###'), '張三');
  });

  test('### 對不到時是空的', () {
    expect(rule(html).getString(r'class.info@text##譯者：(\S+)##$1###'), '');
  });

  test('### 的取代式夾了別的字也只交出那一段', () {
    expect(
      rule(html).getString(
        r'class.read@href##/book/(\d+)/##https://q.test/api/$1.json###',
      ),
      'https://q.test/api/123.json',
    );
    expect(
      rule(html).getStringList(
        r'class.read@href##/book/(\d+)/##https://q.test/api/$1.json###',
      ),
      ['https://q.test/api/123.json'],
    );
  });

  // 同 Legado `split("##")`：切出第四段才是只換第一個，取代式結尾的 `#`
  // 照字面留著；第四段之後還有字也一樣是只換第一個。
  test('取代式結尾只有一個 # 時照字面、每一處都換', () {
    expect(rule('<p>甲乙甲</p>').getString(r'p@text##甲##丙#'), '丙#乙丙#');
  });

  test('### 後面還有字也是只換第一個', () {
    expect(rule(html).getString(r'class.info@text##作者：(\S+)##$1###x'), '張三');
    expect(rule(html).getString(r'class.info@text##作者：(\S+)##$1####'), '張三');
  });

  test('正則寫壞時 ### 交出取代式、## 照純文字取代', () {
    expect(rule(html).getString(r'class.info@text##作者：(##X###'), 'X');
    expect(rule('<p>甲(乙</p>').getString(r'p@text##(乙##丙'), '甲丙');
  });
}
