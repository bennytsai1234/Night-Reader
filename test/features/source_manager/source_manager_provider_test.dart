import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:night_reader/core/constant/source_type.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/services/check_source_service.dart';
import 'package:night_reader/core/services/network_service.dart';
import 'package:night_reader/features/source_manager/source_manager_provider.dart';
import 'package:night_reader/features/source_manager/widgets/source_item_tile.dart';

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
  Future<List<BookSource>> Function()? getAllPartHandler;
  Completer<void>? deleteByUrlsCompleter;
  Completer<void>? updateEnabledByUrlsCompleter;
  Completer<void>? updateEnabledByUrlCompleter;
  int updateEnabledByUrlsCallCount = 0;
  int updateEnabledByUrlCallCount = 0;
  int updateCustomOrderCallCount = 0;

  @override
  Future<List<BookSource>> getAllPart() async {
    getAllPartCallCount += 1;
    final handler = getAllPartHandler;
    if (handler != null) return handler();
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
    updateEnabledByUrlCallCount += 1;
    await updateEnabledByUrlCompleter?.future;
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
    updateEnabledByUrlsCallCount += 1;
    await updateEnabledByUrlsCompleter?.future;
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
    await deleteByUrlsCompleter?.future;
    for (final url in urls) {
      store.remove(url);
    }
  }

  @override
  Future<void> deleteByUrl(String url) async {
    store.remove(url);
  }

  @override
  Future<void> updateCustomOrder(List<BookSource> sources) async {
    updateCustomOrderCallCount += 1;
    for (var index = 0; index < sources.length; index++) {
      store[sources[index].bookSourceUrl]?.customOrder = index;
    }
  }

  @override
  Future<void> renameGroup(String oldName, String newName) async {
    for (final source in store.values) {
      if (source.bookSourceGroup == oldName) source.bookSourceGroup = newName;
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
  Completer<void>? checkCompleter;
  bool _checking = false;

  @override
  bool get isChecking => _checking;

  @override
  Future<void> loadConfig() async {}

  @override
  Future<SourceCheckReport> check(List<String> urls) async {
    if (_checking) return SourceCheckReport.empty;
    _checking = true;
    checkedUrls.add(List<String>.from(urls));
    await checkCompleter?.future;
    _checking = false;
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

  test('parseSourcesDetailed accepts whitespace before a BOM', () {
    final provider = SourceManagerProvider();

    final parsed = provider.parseSourcesDetailed(
      '  \n\uFEFF  [{"bookSourceName":"A","bookSourceUrl":"https://a.test"}]  ',
    );

    expect(parsed.allSources.single.bookSourceUrl, 'https://a.test');
  });

  test('parseSourcesDetailedAsync accepts a BOM-prefixed payload', () async {
    final provider = SourceManagerProvider();

    final parsed = await provider.parseSourcesDetailedAsync(
      '\uFEFF[{"bookSourceName":"A","bookSourceUrl":"https://a.test"}]',
    );

    expect(parsed.allSources.single.bookSourceName, 'A');
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
      await provider.loadSources();

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
    await provider.loadSources();
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
    await provider.loadSources();
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

  test('custom group filter matches a complete group label only', () async {
    fakeDao.store['https://one.example.com'] = BookSource(
      bookSourceUrl: 'https://one.example.com',
      bookSourceName: '精準分組',
      bookSourceGroup: '待修,常用',
    );
    fakeDao.store['https://two.example.com'] = BookSource(
      bookSourceUrl: 'https://two.example.com',
      bookSourceName: '相似分組',
      bookSourceGroup: '待修復,備用',
    );
    final provider = SourceManagerProvider();
    await provider.loadSources();

    provider.setFilterGroup('待修');

    expect(provider.sources.map((source) => source.bookSourceUrl), [
      'https://one.example.com',
    ]);
    expect(provider.sourceUrlsInGroup('待修'), {'https://one.example.com'});
  });

  test('sourceUrlsInGroup is not limited by the active list filter', () async {
    fakeDao.store['https://enabled.example.com'] = BookSource(
      bookSourceUrl: 'https://enabled.example.com',
      bookSourceName: '啟用源',
      bookSourceGroup: '常用',
      enabled: true,
    );
    fakeDao.store['https://disabled.example.com'] = BookSource(
      bookSourceUrl: 'https://disabled.example.com',
      bookSourceName: '停用源',
      bookSourceGroup: '常用',
      enabled: false,
    );
    final provider = SourceManagerProvider();
    await provider.loadSources();
    provider.setFilterGroup('已啟用');

    expect(provider.sources, hasLength(1));
    expect(provider.sourceUrlsInGroup('常用'), {
      'https://enabled.example.com',
      'https://disabled.example.com',
    });
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

  test(
    'select all and invert only change sources visible in the filter',
    () async {
      fakeDao.store['https://enabled.example.com'] = BookSource(
        bookSourceUrl: 'https://enabled.example.com',
        bookSourceName: '啟用源',
        enabled: true,
      );
      fakeDao.store['https://disabled.example.com'] = BookSource(
        bookSourceUrl: 'https://disabled.example.com',
        bookSourceName: '停用源',
        enabled: false,
      );
      final provider = SourceManagerProvider();
      await provider.loadSources();
      provider.toggleSelect('https://disabled.example.com');
      provider.setFilterGroup('已啟用');

      provider.selectAll();
      expect(provider.selectedUrls, {
        'https://enabled.example.com',
        'https://disabled.example.com',
      });

      provider.selectAll();
      expect(provider.selectedUrls, {'https://disabled.example.com'});

      provider.revertSelection();
      expect(provider.selectedUrls, {
        'https://enabled.example.com',
        'https://disabled.example.com',
      });
    },
  );

  test(
    'selectedUrls cannot be mutated without provider notification',
    () async {
      fakeDao.store['https://one.example.com'] = BookSource(
        bookSourceUrl: 'https://one.example.com',
        bookSourceName: '源一',
      );
      final provider = SourceManagerProvider();
      await provider.loadSources();

      expect(
        () => provider.selectedUrls.add('https://outside.example.com'),
        throwsUnsupportedError,
      );
      expect(provider.selectedUrls, isEmpty);
    },
  );

  test('a completed reload cannot be overwritten by an older reload', () async {
    final firstLoad = Completer<List<BookSource>>();
    final secondLoad = Completer<List<BookSource>>();
    var call = 0;
    fakeDao.getAllPartHandler = () {
      call += 1;
      return call == 1 ? firstLoad.future : secondLoad.future;
    };
    final provider = SourceManagerProvider();

    final latest = provider.loadSources();
    secondLoad.complete(<BookSource>[
      BookSource(
        bookSourceUrl: 'https://latest.example.com',
        bookSourceName: '最新結果',
      ),
    ]);
    await latest;
    firstLoad.complete(<BookSource>[
      BookSource(
        bookSourceUrl: 'https://stale.example.com',
        bookSourceName: '過期結果',
      ),
    ]);
    await Future<void>.delayed(Duration.zero);

    expect(provider.sources.single.bookSourceUrl, 'https://latest.example.com');
  });

  test('reload removes selections for sources that no longer exist', () async {
    fakeDao.store['https://one.example.com'] = BookSource(
      bookSourceUrl: 'https://one.example.com',
      bookSourceName: '源一',
    );
    final provider = SourceManagerProvider();
    await provider.loadSources();
    provider.toggleSelect('https://one.example.com');
    fakeDao.store.clear();

    await provider.loadSources();

    expect(provider.selectedUrls, isEmpty);
  });

  test(
    'deleteSelected preserves selections made while deletion is pending',
    () async {
      fakeDao.store['https://one.example.com'] = BookSource(
        bookSourceUrl: 'https://one.example.com',
        bookSourceName: '源一',
      );
      fakeDao.store['https://two.example.com'] = BookSource(
        bookSourceUrl: 'https://two.example.com',
        bookSourceName: '源二',
      );
      final provider = SourceManagerProvider();
      await provider.loadSources();
      provider.toggleSelect('https://one.example.com');
      fakeDao.deleteByUrlsCompleter = Completer<void>();

      final deletion = provider.deleteSelected();
      provider.toggleSelect('https://two.example.com');
      fakeDao.deleteByUrlsCompleter!.complete();
      await deletion;

      expect(provider.selectedUrls, {'https://two.example.com'});
    },
  );

  test('batch mutations ignore repeated triggers while pending', () async {
    fakeDao.store['https://one.example.com'] = BookSource(
      bookSourceUrl: 'https://one.example.com',
      bookSourceName: '源一',
      enabled: false,
    );
    final provider = SourceManagerProvider();
    await provider.loadSources();
    provider.selectAll();
    fakeDao.updateEnabledByUrlsCompleter = Completer<void>();

    final first = provider.batchSetEnabled(true);
    final repeated = provider.batchSetEnabled(true);
    await Future<void>.delayed(Duration.zero);

    expect(fakeDao.updateEnabledByUrlsCallCount, 1);
    expect(provider.isBatchOperationInProgress, isTrue);

    fakeDao.updateEnabledByUrlsCompleter!.complete();
    await Future.wait(<Future<void>>[first, repeated]);
    expect(provider.isBatchOperationInProgress, isFalse);
  });

  test(
    'empty batch group input does not clear the current selection',
    () async {
      fakeDao.store['https://one.example.com'] = BookSource(
        bookSourceUrl: 'https://one.example.com',
        bookSourceName: '源一',
      );
      final provider = SourceManagerProvider();
      await provider.loadSources();
      provider.selectAll();

      await provider.selectionAddToGroups(provider.selectedUrls, '   ');

      expect(provider.selectedUrls, {'https://one.example.com'});
      expect(fakeDao.store['https://one.example.com']?.bookSourceGroup, isNull);
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

  test(
    'checkSelectedSources preserves selections made while checking',
    () async {
      fakeDao.store['https://one.example.com'] = BookSource(
        bookSourceUrl: 'https://one.example.com',
        bookSourceName: '源一',
      );
      fakeDao.store['https://two.example.com'] = BookSource(
        bookSourceUrl: 'https://two.example.com',
        bookSourceName: '源二',
      );
      final checkService = _FakeCheckSourceService(fakeDao)
        ..checkCompleter = Completer<void>();
      final provider = SourceManagerProvider(sourceCheckService: checkService);
      await provider.loadSources();
      provider.toggleSelect('https://one.example.com');

      final checking = provider.checkSelectedSources();
      await Future<void>.delayed(Duration.zero);
      provider.toggleSelect('https://two.example.com');
      checkService.checkCompleter!.complete();
      await checking;

      expect(provider.selectedUrls, {'https://two.example.com'});
    },
  );

  test('repeated source checks do not start a second provider flow', () async {
    fakeDao.store['https://one.example.com'] = BookSource(
      bookSourceUrl: 'https://one.example.com',
      bookSourceName: '源一',
    );
    final checkService = _FakeCheckSourceService(fakeDao)
      ..checkCompleter = Completer<void>();
    final provider = SourceManagerProvider(sourceCheckService: checkService);
    await provider.loadSources();
    provider.selectAll();

    final first = provider.checkSelectedSources();
    await Future<void>.delayed(Duration.zero);
    await provider.checkSelectedSources();

    expect(checkService.checkedUrls, hasLength(1));
    checkService.checkCompleter!.complete();
    await first;
  });

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

  test('filtered lists cannot overwrite the global custom order', () async {
    fakeDao.store['https://visible.example.com'] = BookSource(
      bookSourceUrl: 'https://visible.example.com',
      bookSourceName: '可見',
      bookSourceGroup: '顯示',
      customOrder: 0,
    );
    fakeDao.store['https://hidden.example.com'] = BookSource(
      bookSourceUrl: 'https://hidden.example.com',
      bookSourceName: '隱藏',
      bookSourceGroup: '其他',
      customOrder: 1,
    );
    final provider = SourceManagerProvider();
    await provider.loadSources();
    provider.setFilterGroup('顯示');

    expect(provider.canReorder, isFalse);
    await provider.reorderSource(0, 0);

    expect(fakeDao.updateCustomOrderCallCount, 0);
  });

  test(
    'descending manual order cannot be persisted through drag reorder',
    () async {
      fakeDao.store['https://one.example.com'] = BookSource(
        bookSourceUrl: 'https://one.example.com',
        bookSourceName: '第一個',
        customOrder: 0,
      );
      fakeDao.store['https://two.example.com'] = BookSource(
        bookSourceUrl: 'https://two.example.com',
        bookSourceName: '第二個',
        customOrder: 1,
      );
      final provider = SourceManagerProvider();
      await provider.loadSources();
      provider.toggleSortDesc();

      expect(provider.canReorder, isFalse);
      await provider.reorderSource(0, 1);

      expect(fakeDao.updateCustomOrderCallCount, 0);
    },
  );

  test('provider rejects mutations while a source load is pending', () async {
    final loadCompleter = Completer<List<BookSource>>();
    fakeDao.getAllPartHandler = () => loadCompleter.future;
    final provider = SourceManagerProvider();

    expect(provider.isLoading, isTrue);
    expect(
      await provider.importSources([
        BookSource(
          bookSourceUrl: 'https://new.example.com',
          bookSourceName: '新書源',
        ),
      ]),
      0,
    );
    expect(await provider.deleteNonNovelSources(), 0);
    expect(fakeDao.store, isEmpty);

    loadCompleter.complete(<BookSource>[]);
    await Future<void>.delayed(Duration.zero);
    provider.dispose();
  });

  test('toggle re-finds the source after an out-of-order reload', () async {
    const firstUrl = 'https://first.example.com';
    const secondUrl = 'https://second.example.com';
    fakeDao.store[firstUrl] = BookSource(
      bookSourceUrl: firstUrl,
      bookSourceName: '第一個',
      enabled: true,
    );
    fakeDao.store[secondUrl] = BookSource(
      bookSourceUrl: secondUrl,
      bookSourceName: '第二個',
      enabled: true,
    );
    final provider = SourceManagerProvider();
    await provider.loadSources();
    fakeDao.updateEnabledByUrlCompleter = Completer<void>();

    final toggling = provider.toggleEnabled(provider.sources.first);
    await Future<void>.delayed(Duration.zero);
    fakeDao.store.remove(firstUrl);
    await provider.loadSources();
    fakeDao.updateEnabledByUrlCompleter!.complete();
    await toggling;

    expect(provider.sources.single.bookSourceUrl, secondUrl);
    expect(provider.sources.single.enabled, isTrue);
  });

  test(
    'source mutations are rejected while a source check is running',
    () async {
      const url = 'https://source.example.com';
      fakeDao.store[url] = BookSource(
        bookSourceUrl: url,
        bookSourceName: '書源',
        enabled: true,
      );
      final checkService = _FakeCheckSourceService(fakeDao)
        ..checkCompleter = Completer<void>();
      final provider = SourceManagerProvider(sourceCheckService: checkService);
      await provider.loadSources();
      provider.selectAll();

      final checking = provider.checkSelectedSources();
      await Future<void>.delayed(Duration.zero);
      await provider.toggleEnabled(provider.sources.single);

      expect(provider.isMutationBusy, isTrue);
      expect(fakeDao.updateEnabledByUrlCallCount, 0);
      checkService.checkCompleter!.complete();
      await checking;
    },
  );

  test('renaming the active group follows the new filter name', () async {
    fakeDao.store['https://source.example.com'] = BookSource(
      bookSourceUrl: 'https://source.example.com',
      bookSourceName: '書源',
      bookSourceGroup: '待修',
    );
    final provider = SourceManagerProvider();
    await provider.loadSources();
    provider.setFilterGroup('待修');

    await provider.renameGroup('待修', '已修');

    expect(provider.filterGroup, '已修');
    expect(provider.sources, hasLength(1));
  });

  test('export base names replace path separators and unsafe characters', () {
    expect(
      SourceManagerProvider.sanitizeExportBaseName('站點 A/B\\C?.json'),
      '站點 A_B_C_',
    );
    expect(
      SourceManagerProvider.sanitizeExportBaseName('站點\u0000A\nB'),
      '站點_A_B',
    );
    expect(SourceManagerProvider.sanitizeExportBaseName('..'), 'source');
  });

  test('clipboard export threshold is measured in UTF-8 bytes', () {
    final nonAsciiPayload = '繁' * 200000;

    expect(nonAsciiPayload.length, lessThan(512 * 1024));
    expect(
      SourceManagerProvider.shouldShareExportPayload(nonAsciiPayload),
      isTrue,
    );
  });

  testWidgets('source selection exposes a labeled 48dp semantics control', (
    tester,
  ) async {
    const url = 'https://source.example.com';
    fakeDao.store[url] = BookSource(bookSourceUrl: url, bookSourceName: '測試書源');
    final provider = SourceManagerProvider();
    await provider.loadSources();
    final semantics = tester.ensureSemantics();
    Widget buildTile() {
      return MaterialApp(
        home: Scaffold(
          body: SourceItemTile(
            source: provider.sources.single,
            provider: provider,
            isSelected: provider.selectedUrls.contains(url),
            onTap: () {},
            onLongPress: () {},
            onEdit: () {},
            onShowMenu: () {},
            onEnabledChanged: (_) {},
          ),
        ),
      );
    }

    try {
      await tester.pumpWidget(buildTile());

      final selection = find.byTooltip('選取 測試書源');
      expect(selection, findsOneWidget);
      expect(tester.getSize(selection).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(selection).height, greaterThanOrEqualTo(48));
      expect(
        find.semantics.byLabel('選取 測試書源'),
        isSemantics(
          label: '選取 測試書源',
          isButton: true,
          hasCheckedState: true,
          isChecked: false,
          hasTapAction: true,
        ),
      );

      await tester.tap(selection);
      await tester.pumpWidget(buildTile());
      expect(provider.selectedUrls, contains(url));
      expect(find.byTooltip('取消選取 測試書源'), findsOneWidget);
      expect(
        find.semantics.byLabel('取消選取 測試書源'),
        isSemantics(
          label: '取消選取 測試書源',
          isButton: true,
          hasCheckedState: true,
          isChecked: true,
          hasTapAction: true,
        ),
      );
    } finally {
      semantics.dispose();
      provider.dispose();
    }
  });
}
