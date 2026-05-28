import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:reader/core/constant/source_type.dart';
import 'package:reader/core/database/dao/book_source_dao.dart';
import 'package:reader/core/models/book_source.dart';
import 'package:reader/core/services/check_source_service.dart';
import 'package:reader/core/services/network_service.dart';
import 'package:reader/features/source_manager/source_manager_provider.dart';

final String _importFromUrlTestJson = jsonEncode(<Map<String, dynamic>>[
  {
    'bookSourceName': '書源A',
    'bookSourceUrl': 'https://source-a.test',
    'bookSourceType': 0,
  },
  {
    'bookSourceName': '書源B',
    'bookSourceUrl': 'https://m.suixkan.com#♤guaner',
    'bookSourceType': 0,
    'ruleSearch': <String, dynamic>{
      'bookUrl': r'''##="newWebView\('([^']+)'##$1###''',
    },
  },
]);

class _FakeSourceDao extends Fake implements BookSourceDao {
  final Map<String, BookSource> store = <String, BookSource>{};
  int getByUrlCallCount = 0;
  int getAllPartCallCount = 0;

  @override
  Future<List<BookSource>> getAllPart() async {
    getAllPartCallCount += 1;
    return store.values.toList();
  }

  @override
  Future<List<BookSource>> getAll() async => store.values.toList();

  @override
  Future<BookSource?> getByUrl(String url) async {
    getByUrlCallCount += 1;
    return store[url];
  }

  @override
  Future<void> upsert(BookSource source) async {
    store[source.bookSourceUrl] = source;
  }

  @override
  Future<void> upsertAll(List<BookSource> sources) async {
    for (final source in sources) {
      store[source.bookSourceUrl] = source;
    }
  }

  @override
  Future<void> updateEnabledByUrl(String url, bool enabled) async {
    store[url]?.enabled = enabled;
  }

  @override
  Future<void> updateEnabledExploreByUrl(
    String url,
    bool enabledExplore,
  ) async {
    store[url]?.enabledExplore = enabledExplore;
  }

  @override
  Future<void> updateEnabledByUrls(List<String> urls, bool enabled) async {
    for (final url in urls) {
      store[url]?.enabled = enabled;
    }
  }

  @override
  Future<void> updateEnabledExploreByUrls(
    List<String> urls,
    bool enabledExplore,
  ) async {
    for (final url in urls) {
      store[url]?.enabledExplore = enabledExplore;
    }
  }

  @override
  Future<void> insertOrUpdateAll(List<BookSource> sources) async {
    for (final source in sources) {
      store[source.bookSourceUrl] = source;
    }
  }

  @override
  Future<void> deleteByUrls(List<String> urls) async {
    for (final url in urls) {
      store.remove(url);
    }
  }
}

class _FakeNetworkService extends Fake implements NetworkService {
  _FakeNetworkService(this.body);

  final String body;

  @override
  Dio get dio => Dio()..httpClientAdapter = _StaticResponseAdapter(body);
}

class _StaticResponseAdapter implements HttpClientAdapter {
  _StaticResponseAdapter(this.body);

  final String body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      body,
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['text/plain; charset=utf-8'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _FakeCheckSourceService extends CheckSourceService {
  _FakeCheckSourceService(BookSourceDao sourceDao)
    : super(sourceDao: sourceDao);

  final List<List<String>> checkedUrls = <List<String>>[];
  bool cancelCalled = false;

  @override
  Future<void> loadConfig() async {}

  @override
  Future<SourceCheckReport> check(List<String> urls) async {
    checkedUrls.add(List<String>.from(urls));
    return SourceCheckReport.empty;
  }

  @override
  void cancel() {
    cancelCalled = true;
  }
}

void main() {
  late _FakeSourceDao fakeDao;
  late String networkBody;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    fakeDao = _FakeSourceDao();
    networkBody = '';
    GetIt.instance.registerLazySingleton<BookSourceDao>(() => fakeDao);
    GetIt.instance.registerLazySingleton<NetworkService>(
      () => _FakeNetworkService(networkBody),
    );
  });

  tearDown(() async {
    await GetIt.instance.reset();
  });

  test('parseSources supports Legado source arrays', () {
    final provider = SourceManagerProvider();
    final jsonStr = jsonEncode([
      {
        'bookSourceName': 'BB成人小说',
        'bookSourceUrl': 'https://bbxxxx.com',
        'searchUrl': '/search/?q={{key}}&page={{page}}',
        'enabled': true,
        'enabledExplore': true,
        'ruleSearch': {
          'bookList': 'class.novel-item',
          'name': 'class.info@tag.a@text',
          'bookUrl': 'class.info@tag.a@href',
        },
      },
      {
        'bookSourceName': '第二个书源',
        'bookSourceUrl': 'https://example.com',
        'searchUrl': '/search?q={{key}}',
        'enabled': true,
      },
    ]);

    final parsed = provider.parseSources(jsonStr);

    expect(parsed, hasLength(2));
    expect(parsed.first.bookSourceName, 'BB成人小说');
    expect(parsed.first.bookSourceUrl, 'https://bbxxxx.com');
    expect(parsed.first.ruleSearch?.bookList, 'class.novel-item');
    expect(parsed[1].bookSourceName, '第二个书源');
  });

  test(
    'importFromUrl imports raw JSON string without double encoding',
    () async {
      networkBody = _importFromUrlTestJson;
      final provider = SourceManagerProvider();

      final count = await provider.importFromUrl(
        'https://example.com/sources.json',
      );

      expect(count, 2);
      expect(fakeDao.store.keys, contains('https://source-a.test'));
      expect(
        fakeDao.store['https://m.suixkan.com#♤guaner']?.ruleSearch?.bookUrl,
        r'''##="newWebView\('([^']+)'##$1###''',
      );
    },
  );

  test('importPayloadToText strips BOM and decodes bytes', () {
    final provider = SourceManagerProvider();
    final payload = utf8.encode('\uFEFF[{"bookSourceName":"A"}]');

    final text = provider.importPayloadToTextForTest(payload);

    expect(text, '[{"bookSourceName":"A"}]');
  });

  test(
    'parseSourcesDetailed preserves unsupported sources as disabled entries',
    () {
      final provider = SourceManagerProvider();
      final jsonStr = jsonEncode([
        {
          'bookSourceName': '純小說站',
          'bookSourceUrl': 'https://novel.example.com',
          'bookSourceType': SourceType.book,
        },
        {
          'bookSourceName': '有聲站',
          'bookSourceUrl': 'https://audio.example.com',
          'bookSourceType': SourceType.audio,
        },
        {
          'bookSourceName': '漫畫站',
          'bookSourceUrl': 'https://comic.example.com',
          'bookSourceType': SourceType.book,
        },
      ]);

      final parsed = provider.parseSourcesDetailed(jsonStr);

      expect(parsed.importableSources, hasLength(1));
      expect(parsed.importableSources.single.bookSourceName, '純小說站');
      expect(parsed.unsupportedSources, hasLength(2));
      expect(parsed.allSources, hasLength(3));
      expect(parsed.unsupportedSources.first.enabled, isFalse);
      expect(
        parsed.unsupportedSources.first.bookSourceGroup,
        contains(nonNovelSourceGroupTag),
      );
    },
  );

  test(
    'checkAllSources uses all stored sources instead of current filter',
    () async {
      fakeDao.store['https://enabled.example.com'] = BookSource(
        bookSourceUrl: 'https://enabled.example.com',
        bookSourceName: '啟用源',
        bookSourceType: SourceType.book,
        enabled: true,
      );
      fakeDao.store['https://disabled.example.com'] = BookSource(
        bookSourceUrl: 'https://disabled.example.com',
        bookSourceName: '停用源',
        bookSourceType: SourceType.book,
        enabled: false,
      );

      final provider = SourceManagerProvider();
      await provider.loadSources();
      provider.setFilterGroup('已啟用');

      await provider.checkAllSources();

      expect(provider.lastCheckReport.total, 2);
    },
  );

  test(
    'previewImport keeps unsupported new sources in import buckets',
    () async {
      final provider = SourceManagerProvider();
      final novelSource = BookSource(
        bookSourceUrl: 'https://novel.example.com',
        bookSourceName: '小說源',
        bookSourceType: SourceType.book,
      );
      final unsupportedSource = BookSource(
        bookSourceUrl: 'https://audio.example.com',
        bookSourceName: '有聲源',
        bookSourceType: SourceType.audio,
        enabled: false,
        enabledExplore: false,
        bookSourceGroup: nonNovelSourceGroupTag,
      );

      final preview = await provider.previewImport(
        [novelSource, unsupportedSource],
        unsupportedSources: [unsupportedSource],
      );

      expect(fakeDao.getByUrlCallCount, 0);
      expect(preview.newSources, hasLength(2));
      expect(preview.unsupportedSources, [unsupportedSource]);
    },
  );

  test(
    'importSources preserves existing order and appends new sources',
    () async {
      fakeDao.store['https://old.example.com'] = BookSource(
        bookSourceUrl: 'https://old.example.com',
        bookSourceName: '既有源',
        customOrder: 5,
      );
      fakeDao.store['https://other.example.com'] = BookSource(
        bookSourceUrl: 'https://other.example.com',
        bookSourceName: '其他源',
        customOrder: 6,
      );

      final provider = SourceManagerProvider();

      final count = await provider.importSources([
        BookSource(
          bookSourceUrl: 'https://old.example.com',
          bookSourceName: '更新既有源',
          customOrder: 0,
        ),
        BookSource(
          bookSourceUrl: 'https://new-1.example.com',
          bookSourceName: '新源一',
          customOrder: 0,
        ),
        BookSource(
          bookSourceUrl: 'https://new-2.example.com',
          bookSourceName: '新源二',
          customOrder: 0,
        ),
      ]);

      expect(count, 3);
      expect(fakeDao.store['https://old.example.com']?.customOrder, 5);
      expect(fakeDao.store['https://new-1.example.com']?.customOrder, 7);
      expect(fakeDao.store['https://new-2.example.com']?.customOrder, 8);
    },
  );

  test('deleteNonNovelSources removes existing non-novel sources', () async {
    fakeDao.store['https://novel.example.com'] = BookSource(
      bookSourceUrl: 'https://novel.example.com',
      bookSourceName: '小說源',
      bookSourceType: SourceType.book,
    );
    fakeDao.store['https://audio.example.com'] = BookSource(
      bookSourceUrl: 'https://audio.example.com',
      bookSourceName: '有聲源',
      bookSourceType: SourceType.audio,
      enabledExplore: true,
    );
    fakeDao.store['https://comic.example.com'] = BookSource(
      bookSourceUrl: 'https://comic.example.com',
      bookSourceName: '漫畫源',
      bookSourceType: SourceType.book,
      enabledExplore: true,
    );

    final provider = SourceManagerProvider();
    final affected = await provider.deleteNonNovelSources();

    expect(affected, 2);
    expect(fakeDao.store.keys, contains('https://novel.example.com'));
    expect(fakeDao.store.keys, isNot(contains('https://audio.example.com')));
    expect(fakeDao.store.keys, isNot(contains('https://comic.example.com')));
  });

  test('clearInvalidSources removes login-required sources', () async {
    fakeDao.store['https://valid.example.com'] = BookSource(
      bookSourceUrl: 'https://valid.example.com',
      bookSourceName: '正常源',
      bookSourceType: SourceType.book,
    );
    fakeDao.store['https://login.example.com'] = BookSource(
      bookSourceUrl: 'https://login.example.com',
      bookSourceName: '登入牆源',
      bookSourceType: SourceType.book,
      bookSourceGroup: loginRequiredSourceGroupTag,
    );
    fakeDao.store['https://search-broken.example.com'] = BookSource(
      bookSourceUrl: 'https://search-broken.example.com',
      bookSourceName: '搜尋失效源',
      bookSourceType: SourceType.book,
      bookSourceGroup: searchBrokenSourceGroupTag,
    );

    final provider = SourceManagerProvider();
    await provider.clearInvalidSources();

    expect(fakeDao.store.keys, contains('https://valid.example.com'));
    expect(fakeDao.store.keys, isNot(contains('https://login.example.com')));
    expect(fakeDao.store.keys, contains('https://search-broken.example.com'));
  });

  test('filterGroup supports enabled and disabled explore buckets', () async {
    fakeDao.store['https://explore-on.example.com'] = BookSource(
      bookSourceUrl: 'https://explore-on.example.com',
      bookSourceName: '可發現源',
      bookSourceType: SourceType.book,
      exploreUrl: '/explore',
      enabledExplore: true,
    );
    fakeDao.store['https://explore-off.example.com'] = BookSource(
      bookSourceUrl: 'https://explore-off.example.com',
      bookSourceName: '停用發現源',
      bookSourceType: SourceType.book,
      exploreUrl: '/explore',
      enabledExplore: false,
    );

    final provider = SourceManagerProvider();
    await provider.loadSources();

    provider.setFilterGroup('已啟用發現');
    expect(provider.sources.map((source) => source.bookSourceUrl), [
      'https://explore-on.example.com',
    ]);

    provider.setFilterGroup('已禁用發現');
    expect(provider.sources.map((source) => source.bookSourceUrl), [
      'https://explore-off.example.com',
    ]);
  });

  test('source state toggles update local list without full reload', () async {
    fakeDao.store['https://one.example.com'] = BookSource(
      bookSourceUrl: 'https://one.example.com',
      bookSourceName: '源一',
      bookSourceType: SourceType.book,
      exploreUrl: '/explore',
      enabled: true,
      enabledExplore: true,
    );
    fakeDao.store['https://two.example.com'] = BookSource(
      bookSourceUrl: 'https://two.example.com',
      bookSourceName: '源二',
      bookSourceType: SourceType.book,
      exploreUrl: '/explore',
      enabled: true,
      enabledExplore: true,
    );

    final provider = SourceManagerProvider();
    await provider.loadSources();
    final loadCountAfterInitialLoad = fakeDao.getAllPartCallCount;

    await provider.toggleEnabled(provider.sources.first);
    expect(fakeDao.getAllPartCallCount, loadCountAfterInitialLoad);
    provider.setFilterGroup('已禁用');
    expect(provider.sources.map((source) => source.bookSourceUrl), [
      'https://one.example.com',
    ]);

    provider.toggleSelect('https://one.example.com');
    provider.toggleSelect('https://two.example.com');
    await provider.batchSetEnabledExplore(false);
    expect(fakeDao.getAllPartCallCount, loadCountAfterInitialLoad);
    provider.setFilterGroup('已禁用發現');
    expect(provider.sources.map((source) => source.bookSourceUrl), [
      'https://one.example.com',
      'https://two.example.com',
    ]);
  });

  test(
    'checkSelectedInterval selects sources between first and last selection',
    () async {
      for (var index = 0; index < 4; index++) {
        fakeDao.store['https://$index.example.com'] = BookSource(
          bookSourceUrl: 'https://$index.example.com',
          bookSourceName: '源$index',
          bookSourceType: SourceType.book,
          customOrder: index,
        );
      }

      final provider = SourceManagerProvider();
      await provider.loadSources();

      provider.toggleSelect('https://0.example.com');
      provider.toggleSelect('https://2.example.com');
      provider.checkSelectedInterval();

      expect(
        provider.selectedUrls,
        containsAll(<String>[
          'https://0.example.com',
          'https://1.example.com',
          'https://2.example.com',
        ]),
      );
    },
  );

  test('selection group changes clear selected urls after applying', () async {
    fakeDao.store['https://one.example.com'] = BookSource(
      bookSourceUrl: 'https://one.example.com',
      bookSourceName: '源一',
      bookSourceType: SourceType.book,
    );
    fakeDao.store['https://two.example.com'] = BookSource(
      bookSourceUrl: 'https://two.example.com',
      bookSourceName: '源二',
      bookSourceType: SourceType.book,
      bookSourceGroup: '待移除',
    );

    final provider = SourceManagerProvider();
    await provider.loadSources();

    provider.selectAll();
    expect(provider.selectedUrls, hasLength(2));

    await provider.selectionAddToGroups(provider.selectedUrls, '新分組');

    expect(provider.selectedUrls, isEmpty);
    expect(fakeDao.store['https://one.example.com']?.bookSourceGroup, '新分組');
    expect(
      fakeDao.store['https://two.example.com']?.bookSourceGroup,
      contains('新分組'),
    );

    provider.selectAll();
    await provider.selectionRemoveFromGroups(provider.selectedUrls, '新分組');

    expect(provider.selectedUrls, isEmpty);
    expect(
      fakeDao.store.values.map((source) => source.bookSourceGroup),
      isNot(contains(contains('新分組'))),
    );
  });

  test(
    'checkSelectedSources clears selected urls after check completes',
    () async {
      fakeDao.store['https://one.example.com'] = BookSource(
        bookSourceUrl: 'https://one.example.com',
        bookSourceName: '源一',
        bookSourceType: SourceType.book,
      );
      fakeDao.store['https://two.example.com'] = BookSource(
        bookSourceUrl: 'https://two.example.com',
        bookSourceName: '源二',
        bookSourceType: SourceType.book,
      );
      final checkService = _FakeCheckSourceService(fakeDao);
      final provider = SourceManagerProvider(sourceCheckService: checkService);
      await provider.loadSources();

      provider.selectAll();
      expect(provider.selectedUrls, hasLength(2));

      await provider.checkSelectedSources();

      expect(checkService.checkedUrls.single, hasLength(2));
      expect(provider.selectedUrls, isEmpty);
    },
  );

  test('cancelSourceCheck clears selected urls immediately', () async {
    fakeDao.store['https://one.example.com'] = BookSource(
      bookSourceUrl: 'https://one.example.com',
      bookSourceName: '源一',
      bookSourceType: SourceType.book,
    );
    final checkService = _FakeCheckSourceService(fakeDao);
    final provider = SourceManagerProvider(sourceCheckService: checkService);
    await provider.loadSources();

    provider.selectAll();
    provider.cancelSourceCheck();

    expect(checkService.cancelCalled, isTrue);
    expect(provider.selectedUrls, isEmpty);
  });
}
