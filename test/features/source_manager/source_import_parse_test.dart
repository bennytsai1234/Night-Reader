import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/features/source_manager/source_manager_provider.dart';

class _UnusedDao extends Fake implements BookSourceDao {}

void main() {
  test('sources whose numbers are written as strings still import', () {
    // 源倉庫（yckceo.com）給的書源把 lastUpdateTime 寫成字串；Legado 照收。
    const json = '''
[{
  "bookSourceName": "番茄小说",
  "bookSourceUrl": "https://fanqienovel.com",
  "bookSourceType": "0",
  "customOrder": "3",
  "enabled": "true",
  "enabledExplore": 0,
  "lastUpdateTime": "1792825494301",
  "respondTime": "180000",
  "weight": "0",
  "searchUrl": "/search?q={{key}}",
  "ruleSearch": {"bookList": "class.item", "name": "a@text"}
}]
''';

    final parsed = SourceImportService(dao: _UnusedDao())
        .parseSourcesDetailed(json);

    expect(parsed.importableSources, hasLength(1));
    final source = parsed.importableSources.single;
    expect(source.lastUpdateTime, 1792825494301);
    expect(source.customOrder, 3);
    expect(source.respondTime, 180000);
    expect(source.enabled, isTrue);
    expect(source.enabledExplore, isFalse);
  });

  test('source switches default on only when missing', () {
    const json = '''
[{"bookSourceName": "a", "bookSourceUrl": "https://a.test",
  "enabled": "disabled", "enabledExplore": "", "enabledCookieJar": "1"},
 {"bookSourceName": "b", "bookSourceUrl": "https://b.test"}]
''';

    final sources = SourceImportService(dao: _UnusedDao())
        .parseSourcesDetailed(json)
        .importableSources;

    expect(sources[0].enabled, isFalse);
    expect(sources[0].enabledExplore, isFalse);
    expect(sources[0].enabledCookieJar, isTrue);
    expect(sources[1].enabled, isTrue);
    expect(sources[1].enabledExplore, isTrue);
  });

  test('novel categories named after anime or films do not mark a novel '
      'site as non-novel', () {
    const json = '''
[{
  "bookSourceName": "番茄小说",
  "bookSourceUrl": "https://fanqienovel.com",
  "exploreUrl": "[{\\"title\\":\\"动漫衍生\\"},{\\"title\\":\\"影视剧本\\"}]"
}, {
  "bookSourceName": "包子漫画",
  "bookSourceUrl": "https://cn.baozimh.com"
}]
''';

    final parsed = SourceImportService(dao: _UnusedDao())
        .parseSourcesDetailed(json);

    expect(parsed.importableSources.map((s) => s.bookSourceName), ['番茄小说']);
    expect(parsed.unsupportedSources.map((s) => s.bookSourceName), ['包子漫画']);
  });
}
