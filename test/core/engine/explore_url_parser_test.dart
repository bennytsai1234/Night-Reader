import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/explore_url_parser.dart';

/// 發現規則的 JSON 照 Legado 用 Gson 寬鬆模式讀。
void main() {
  test('字串裡的 ,] 與 ,} 照原樣留著', () {
    final kinds = ExploreUrlParser.parse(
      '[{"title":"排行,}","url":"https://books.example/list?filter=[1,]"}]',
    );
    expect(kinds.single.title, '排行,}');
    expect(kinds.single.url, 'https://books.example/list?filter=[1,]');
  });

  test('外層多一個逗號照收', () {
    final kinds = ExploreUrlParser.parse(
      '[{"title":"玄幻","url":"/x/1",},{"title":"都市","url":"/x/2"},]',
    );
    expect(kinds.map((k) => k.title), ['玄幻', '都市']);
  });

  test('標準 JSON 照標準讀：空的欄位名照收', () {
    final kinds = ExploreUrlParser.parse(
      '[{"title":"排行","url":"/a","":"metadata"}]',
    );
    expect(kinds.single.title, '排行');
  });

  test('單一物件的字串裡的逗號也留著', () {
    final kinds = ExploreUrlParser.parse(
      '{"title":"排行","url":"/list?filter={a,}"}',
    );
    expect(kinds.single.url, '/list?filter={a,}');
  });
}
