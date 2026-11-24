import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/analyze_rule.dart';
import 'package:night_reader/core/models/source/book_source.dart';

import '../../test_helper.dart';

/// 含 `{{ }}`、`@get:` 的規則，`##` 的取代等組好字才切（同 Legado
/// `SourceRule.makeUpRule`）：`{{ }}` 裡的 `##` 屬於那段子規則，組字之後
/// 整條結果裡的 `##` 才是整條規則的取代。先切整條會把 `{{$..name##小说}}`
/// 切斷，`{{$..name` 原樣印出來（2026-11-15 AI 找書實跑，企鹅阅读的分類）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupTestDI();

  AnalyzeRule rule(dynamic content) =>
      AnalyzeRule(source: BookSource(bookSourceUrl: 'https://q.test'))
          .setContent(content, baseUrl: 'https://q.test/search');

  const book = {
    'finished': 'true',
    'cate': {'shortName': '玄幻小说'},
    'chapinfo': {'lastChapterUpdateTime': '2023-05-01 12:00'},
  };

  test(r'{{ }} 裡的 ## 是那段子規則自己的取代', () {
    expect(
      rule(book).getString(
        "{{java.getString('\$.finished')=='true'?'完结':'连载'}}\n"
        r'{{$..shortName##小说}}',
      ),
      '完结\n玄幻',
    );
    expect(
      rule(book).getString(r'更新：{{$.chapinfo.lastChapterUpdateTime##\s.*}}'),
      '更新：2023-05-01',
    );
  });

  test('組好的字之後的 ## 是整條規則的取代', () {
    expect(rule(book).getString(r"{{'甲乙丙'}}##乙"), '甲丙');
    // ### 只交出第一個對到的那段換過的樣子（Legado replaceFirst）。
    expect(rule(book).getString(r"{{'甲乙乙'}}##乙##丁###"), '丁');
  });

  test(r'取代式是組出來的：$.title##{{…}} 照 JSON 取字再換', () {
    final content = {'title': '第一章 開始', 'cut': '第一章 '};
    expect(rule(content).getString(r'$.title##{{$.cut}}'), '開始');
  });

  test(r'## 之後的 $1 是取代式的群組，不是正則規則（同 Legado splitRegex）', () {
    final content = {'title': '第一章 開始', 'cut': '第一章 '};
    expect(rule(content).getString(r'$.title##({{$.cut}})##[$1]'), '[第一章 ]開始');
  });

  test('網頁的簡介：{{@@…}} 裡的 ## 不會把規則切斷（大唐小說、歪歪書庫的寫法）', () {
    const html =
        '<html><head>'
        '<meta property="og:description" content="穿越了。一路變強！">'
        '<meta property="og:novel:update_time" content="2024-01-02 03:04">'
        '</head><body></body></html>';
    expect(
      rule(html)
          .getString(r'{{@@[property$=description]@content##(^|[。！？]+)##$1|}}'),
      '|穿越了。|一路變強！|',
    );
    expect(
      rule(html).getString(
        '更新：{{@@[property="og:novel:update_time"]@content##\\s##_}}\n'
        '簡介：{{@@[property="og:description"]@content}}##。##，',
      ),
      '更新：2024-01-02_03:04\n簡介：穿越了，一路變強！',
    );
  });

  test('沒有 {{ }} 的規則照舊先切', () {
    expect(rule(book).getString(r'$.cate.shortName##小说'), '玄幻');
  });
}
