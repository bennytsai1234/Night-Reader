import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/models/book_source.dart';
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

  test('text fields written as objects, arrays or numbers still import', () {
    // 牛颜小说网把 header 寫成物件；Legado 的 StringJsonDeserializer 把物件、
    // 陣列轉成 JSON 文字，數字、true/false 轉成原本的文字。
    const json = '''
[{
  "bookSourceName": "牛颜小说网",
  "bookSourceUrl": "https://www.niuyan123.link",
  "header": {"User-Agent": "Mozilla/5.0", "Referer": "https://a.test/"},
  "loginUi": [{"name": "帳號", "type": "text"}],
  "exploreUrl": [{"title": "玄幻", "url": "/x/1"}],
  "concurrentRate": 1000,
  "bookSourceGroup": 1,
  "ruleSearch": {"bookList": ".item", "checkKeyWord": 123, "name": true},
  "ruleToc": {"chapterList": "li", "isVolume": false, "nextPage": "a@href"}
}]
''';

    final source = SourceImportService(dao: _UnusedDao())
        .parseSourcesDetailed(json)
        .importableSources
        .single;

    expect(
      source.header,
      '{"User-Agent":"Mozilla/5.0","Referer":"https://a.test/"}',
    );
    expect(source.loginUi, '[{"name":"帳號","type":"text"}]');
    expect(source.exploreUrl, '[{"title":"玄幻","url":"/x/1"}]');
    expect(source.concurrentRate, '1000');
    expect(source.bookSourceGroup, '1');
    expect(source.ruleSearch?.checkKeyWord, '123');
    expect(source.ruleSearch?.name, 'true');
    expect(source.ruleToc?.isVolume, 'false');
    expect(source.ruleToc?.nextTocUrl, 'a@href');
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

  test('novel categories named after anime or films keep a novel site a '
      'novel', () {
    const json = '''
[{
  "bookSourceName": "番茄小说",
  "bookSourceUrl": "https://fanqienovel.com",
  "exploreUrl": "[{\\"title\\":\\"动漫衍生\\"},{\\"title\\":\\"影视剧本\\"}]"
}]
''';

    final source = SourceImportService(dao: _UnusedDao())
        .parseSourcesDetailed(json)
        .importableSources
        .single;

    expect(source.sourceKind, BookSourceKind.novel);
  });

  test('comic and audio sources are kept, typed and left enabled; film '
      'sources are disabled', () {
    const json = '''
[{"bookSourceName": "包子漫画", "bookSourceUrl": "https://cn.baozimh.com"},
 {"bookSourceName": "懒人听书", "bookSourceUrl": "https://lrts.me"},
 {"bookSourceName": "图源", "bookSourceUrl": "https://img.test",
  "bookSourceType": 2},
 {"bookSourceName": "电影天堂", "bookSourceUrl": "https://movie.test"},
 {"bookSourceName": "文件站", "bookSourceUrl": "https://file.test",
  "bookSourceType": 3}]
''';

    final parsed = SourceImportService(dao: _UnusedDao())
        .parseSourcesDetailed(json);

    expect(
      {
        for (final s in parsed.importableSources)
          s.bookSourceName: (s.bookSourceType, s.enabled),
      },
      {'包子漫画': (2, true), '懒人听书': (1, true), '图源': (2, true)},
    );
    expect(parsed.unsupportedSources.map((s) => s.bookSourceName), [
      '电影天堂',
      '文件站',
    ]);
    for (final source in parsed.unsupportedSources) {
      expect(source.enabled, isFalse);
      expect(source.groupTags, contains(nonNovelSourceGroupTag));
    }
  });

  test(
    'sources an older version disabled as non-novel come back as comics',
    () {
      const json = '''
[{"bookSourceName": "包子漫画", "bookSourceUrl": "https://cn.baozimh.com",
  "bookSourceGroup": "漫畫,非小說源,異常", "enabled": false,
  "enabledExplore": false}]
''';

      final source = SourceImportService(dao: _UnusedDao())
          .parseSourcesDetailed(json)
          .importableSources
          .single;

      expect(source.sourceKind, BookSourceKind.comic);
      expect(source.groupTags, {'漫畫'});
      expect(source.enabled, isTrue);
      expect(source.enabledExplore, isTrue);
    },
  );
}
