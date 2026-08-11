import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/source/explore_kind.dart';
import 'package:night_reader/features/explore/explore_provider.dart';

class _FakeSourceDao extends Fake implements BookSourceDao {
  List<BookSource> sources = [];
  int getDiscoveryPartCallCount = 0;
  final StreamController<List<BookSource>> _controller =
      StreamController<List<BookSource>>.broadcast();

  @override
  Future<List<BookSource>> getEnabled() async =>
      sources.where((source) => source.enabled).toList();

  @override
  Future<List<BookSource>> getAll() async => List<BookSource>.from(sources);

  @override
  Stream<List<BookSource>> watchAll() => _controller.stream;

  @override
  Future<List<BookSource>> getAllPart() async => List<BookSource>.from(sources);

  @override
  Stream<List<BookSource>> watchAllPart() => _controller.stream;

  @override
  Future<List<BookSource>> getDiscoveryPart() async {
    getDiscoveryPartCallCount++;
    return List<BookSource>.from(sources);
  }

  @override
  Stream<List<BookSource>> watchDiscoveryPart() async* {
    yield List<BookSource>.from(sources);
    yield* _controller.stream;
  }

  @override
  Future<BookSource?> getByUrl(String url) async =>
      sources.where((source) => source.bookSourceUrl == url).firstOrNull;

  @override
  Future<void> updateCustomOrderByUrl(String url, int customOrder) async {
    final source = await getByUrl(url);
    if (source != null) source.customOrder = customOrder;
  }

  void pushSources(List<BookSource> nextSources) {
    sources = List<BookSource>.from(nextSources);
    _controller.add(List<BookSource>.from(sources));
  }

  Future<void> dispose() async {
    await _controller.close();
  }
}

Future<void> _settleAsync() async {
  await Future<void>.delayed(const Duration(milliseconds: 10));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeSourceDao fakeSourceDao;

  setUp(() {
    fakeSourceDao = _FakeSourceDao();
    addTearDown(fakeSourceDao.dispose);
  });

  test('toggleExpand waits for async kinds and reuses cache', () async {
    fakeSourceDao.sources = [
      BookSource(
        bookSourceUrl: 'source://bb',
        bookSourceName: 'BB成人小说',
        enabledExplore: true,
        exploreUrl: '<js>java.ajax("https://bbxxxx.com/")</js>',
      ),
    ];

    final kindsCompleter = Completer<List<ExploreKind>>();
    var loaderCalls = 0;
    final provider = ExploreProvider(
      sourceDao: fakeSourceDao,
      kindsLoader: (exploreUrl, {source}) async {
        loaderCalls++;
        expect(exploreUrl, contains('java.ajax'));
        expect(source?.bookSourceUrl, 'source://bb');
        return kindsCompleter.future;
      },
    );
    addTearDown(provider.dispose);

    await _settleAsync();
    expect(provider.sources, hasLength(1));

    final expandFuture = provider.toggleExpand(0);
    expect(provider.expandedIndex, 0);
    expect(provider.isLoadingKinds, isTrue);
    expect(provider.expandedKinds, isEmpty);

    kindsCompleter.complete([
      const ExploreKind(
        title: '最新',
        url: 'https://bbxxxx.com/rank/new/{{page}}.html',
      ),
    ]);
    await expandFuture;

    expect(provider.isLoadingKinds, isFalse);
    expect(provider.expandedKinds, [
      const ExploreKind(
        title: '最新',
        url: 'https://bbxxxx.com/rank/new/{{page}}.html',
      ),
    ]);
    expect(loaderCalls, 1);

    await provider.toggleExpand(0);
    expect(provider.expandedIndex, -1);

    await provider.toggleExpand(0);
    expect(provider.isLoadingKinds, isFalse);
    expect(provider.expandedKinds, hasLength(1));
    expect(loaderCalls, 1);
  });

  test('refreshKindsCache reloads currently expanded source', () async {
    fakeSourceDao.sources = [
      BookSource(
        bookSourceUrl: 'source://bb',
        bookSourceName: 'BB成人小说',
        enabledExplore: true,
        exploreUrl: '最新::https://example.com/new',
      ),
    ];

    final responses = <List<ExploreKind>>[
      [const ExploreKind(title: '最新', url: 'https://example.com/new')],
      [const ExploreKind(title: '熱門', url: 'https://example.com/hot')],
    ];
    var loaderCalls = 0;
    final provider = ExploreProvider(
      sourceDao: fakeSourceDao,
      kindsLoader: (exploreUrl, {source}) async => responses[loaderCalls++],
    );
    addTearDown(provider.dispose);

    await _settleAsync();
    await provider.toggleExpand(0);
    expect(provider.expandedKinds.first.title, '最新');
    expect(loaderCalls, 1);

    await provider.refreshKindsCache(provider.sources.first);
    expect(provider.expandedKinds.first.title, '熱門');
    expect(loaderCalls, 2);
  });

  test('交錯分類請求只讓目前書源更新可見狀態', () async {
    fakeSourceDao.sources = [
      BookSource(
        bookSourceUrl: 'source://a',
        bookSourceName: '書源 A',
        enabledExplore: true,
        exploreUrl: 'A::https://example.com/a',
      ),
      BookSource(
        bookSourceUrl: 'source://b',
        bookSourceName: '書源 B',
        enabledExplore: true,
        exploreUrl: 'B::https://example.com/b',
      ),
    ];
    final aCompleter = Completer<List<ExploreKind>>();
    final bCompleter = Completer<List<ExploreKind>>();
    final provider = ExploreProvider(
      sourceDao: fakeSourceDao,
      kindsLoader: (exploreUrl, {source}) {
        return source!.bookSourceUrl == 'source://a'
            ? aCompleter.future
            : bCompleter.future;
      },
    );
    addTearDown(provider.dispose);

    await _settleAsync();
    final firstRequest = provider.toggleExpand(0);
    final secondRequest = provider.toggleExpand(1);

    aCompleter.completeError(StateError('A 載入失敗'));
    await firstRequest;
    expect(provider.expandedIndex, 1);
    expect(provider.isLoadingKinds, isTrue);
    expect(provider.expandedKinds, isEmpty);

    bCompleter.complete([
      const ExploreKind(title: 'B 分類', url: 'https://example.com/b/1'),
    ]);
    await secondRequest;
    expect(provider.isLoadingKinds, isFalse);
    expect(provider.expandedKinds.single.title, 'B 分類');
  });

  test('舊請求成功結果可進快取，但不覆寫目前書源', () async {
    fakeSourceDao.sources = [
      BookSource(
        bookSourceUrl: 'source://a',
        bookSourceName: '書源 A',
        enabledExplore: true,
        exploreUrl: 'A::https://example.com/a',
      ),
      BookSource(
        bookSourceUrl: 'source://b',
        bookSourceName: '書源 B',
        enabledExplore: true,
        exploreUrl: 'B::https://example.com/b',
      ),
    ];
    final aCompleter = Completer<List<ExploreKind>>();
    final bCompleter = Completer<List<ExploreKind>>();
    var aCalls = 0;
    final provider = ExploreProvider(
      sourceDao: fakeSourceDao,
      kindsLoader: (exploreUrl, {source}) {
        if (source!.bookSourceUrl == 'source://a') {
          aCalls++;
          return aCompleter.future;
        }
        return bCompleter.future;
      },
    );
    addTearDown(provider.dispose);

    await _settleAsync();
    final firstRequest = provider.toggleExpand(0);
    final secondRequest = provider.toggleExpand(1);

    aCompleter.complete([
      const ExploreKind(title: 'A 分類', url: 'https://example.com/a/1'),
    ]);
    await firstRequest;
    expect(provider.expandedKinds, isEmpty);
    expect(provider.isLoadingKinds, isTrue);

    bCompleter.complete([
      const ExploreKind(title: 'B 分類', url: 'https://example.com/b/1'),
    ]);
    await secondRequest;
    await provider.toggleExpand(1);
    await provider.toggleExpand(0);

    expect(provider.expandedKinds.single.title, 'A 分類');
    expect(aCalls, 1);
  });

  test('同一書源較新的請求完成後，舊請求不得覆寫新快取', () async {
    fakeSourceDao.sources = [
      BookSource(
        bookSourceUrl: 'source://same',
        bookSourceName: '同一書源',
        enabledExplore: true,
        exploreUrl: '分類::https://example.com/same',
      ),
    ];
    final oldCompleter = Completer<List<ExploreKind>>();
    final newCompleter = Completer<List<ExploreKind>>();
    var loaderCalls = 0;
    final provider = ExploreProvider(
      sourceDao: fakeSourceDao,
      kindsLoader: (exploreUrl, {source}) {
        loaderCalls++;
        return loaderCalls == 1 ? oldCompleter.future : newCompleter.future;
      },
    );
    addTearDown(provider.dispose);

    await _settleAsync();
    final oldRequest = provider.toggleExpand(0);
    await provider.toggleExpand(0);
    final newRequest = provider.toggleExpand(0);

    newCompleter.complete([
      const ExploreKind(title: '新分類', url: 'https://example.com/new'),
    ]);
    await newRequest;
    expect(provider.expandedKinds.single.title, '新分類');

    oldCompleter.complete([
      const ExploreKind(title: '舊分類', url: 'https://example.com/old'),
    ]);
    await oldRequest;
    expect(provider.expandedKinds.single.title, '新分類');

    await provider.toggleExpand(0);
    await provider.toggleExpand(0);
    expect(provider.expandedKinds.single.title, '新分類');
    expect(loaderCalls, 2);
  });

  test('展開中的書源規則更新會失效舊請求並自動載入新分類', () async {
    fakeSourceDao.sources = [
      BookSource(
        bookSourceUrl: 'source://same',
        bookSourceName: '同一書源',
        enabledExplore: true,
        exploreUrl: '舊分類::https://example.com/old',
      ),
    ];
    final oldCompleter = Completer<List<ExploreKind>>();
    final newCompleter = Completer<List<ExploreKind>>();
    final loaderInputs = <String?>[];
    final provider = ExploreProvider(
      sourceDao: fakeSourceDao,
      kindsLoader: (exploreUrl, {source}) {
        loaderInputs.add(exploreUrl);
        return exploreUrl?.contains('新分類') == true
            ? newCompleter.future
            : oldCompleter.future;
      },
    );
    addTearDown(provider.dispose);

    await _settleAsync();
    final oldRequest = provider.toggleExpand(0);
    fakeSourceDao.pushSources([
      BookSource(
        bookSourceUrl: 'source://same',
        bookSourceName: '同一書源',
        enabledExplore: true,
        exploreUrl: '新分類::https://example.com/new',
      ),
    ]);
    await _settleAsync();

    expect(provider.isLoadingKinds, isTrue);
    newCompleter.complete([
      const ExploreKind(title: '新分類', url: 'https://example.com/new'),
    ]);
    await _settleAsync();
    expect(provider.expandedKinds.single.title, '新分類');

    oldCompleter.complete([
      const ExploreKind(title: '舊分類', url: 'https://example.com/old'),
    ]);
    await oldRequest;
    expect(provider.expandedKinds.single.title, '新分類');
    expect(loaderInputs, <String?>[
      '舊分類::https://example.com/old',
      '新分類::https://example.com/new',
    ]);
  });

  test('changing exploreUrl invalidates in-memory kinds cache', () async {
    fakeSourceDao.sources = [
      BookSource(
        bookSourceUrl: 'source://same',
        bookSourceName: '同一書源',
        enabledExplore: true,
        exploreUrl: '舊分類::https://example.com/old',
      ),
    ];

    final loaderInputs = <String?>[];
    final provider = ExploreProvider(
      sourceDao: fakeSourceDao,
      kindsLoader: (exploreUrl, {source}) async {
        loaderInputs.add(exploreUrl);
        return <ExploreKind>[
          ExploreKind(
            title: exploreUrl?.contains('新分類') == true ? '新分類' : '舊分類',
            url: exploreUrl,
          ),
        ];
      },
    );
    addTearDown(provider.dispose);

    await _settleAsync();
    await provider.toggleExpand(0);
    expect(provider.expandedKinds.first.title, '舊分類');

    await provider.toggleExpand(0);
    fakeSourceDao.pushSources([
      BookSource(
        bookSourceUrl: 'source://same',
        bookSourceName: '同一書源',
        enabledExplore: true,
        exploreUrl: '新分類::https://example.com/new',
      ),
    ]);
    await _settleAsync();

    await provider.toggleExpand(0);
    expect(provider.expandedKinds.first.title, '新分類');
    expect(loaderInputs, <String?>[
      '舊分類::https://example.com/old',
      '新分類::https://example.com/new',
    ]);
  });

  test(
    'watchAll refreshes sources after import without recreating provider',
    () async {
      fakeSourceDao.sources = [
        BookSource(
          bookSourceUrl: 'source://one',
          bookSourceName: '第一個書源',
          enabled: true,
          enabledExplore: true,
          exploreUrl: '最新::https://example.com/one',
        ),
      ];

      final provider = ExploreProvider(
        sourceDao: fakeSourceDao,
        kindsLoader: (exploreUrl, {source}) async => const [],
      );
      addTearDown(provider.dispose);

      await _settleAsync();
      expect(provider.sources.map((source) => source.bookSourceUrl), [
        'source://one',
      ]);

      fakeSourceDao.pushSources([
        ...fakeSourceDao.sources,
        BookSource(
          bookSourceUrl: 'source://two',
          bookSourceName: '第二個書源',
          enabled: true,
          enabledExplore: true,
          exploreUrl: '最新::https://example.com/two',
        ),
      ]);

      await _settleAsync();
      expect(provider.sources.map((source) => source.bookSourceUrl), [
        'source://one',
        'source://two',
      ]);
    },
  );

  test(
    'initial load uses discovery stream without extra one-shot query',
    () async {
      fakeSourceDao.sources = [
        BookSource(
          bookSourceUrl: 'source://one',
          bookSourceName: '第一個書源',
          enabled: true,
          enabledExplore: true,
          exploreUrl: '最新::https://example.com/one',
        ),
      ];

      final provider = ExploreProvider(
        sourceDao: fakeSourceDao,
        kindsLoader: (exploreUrl, {source}) async => const [],
      );
      addTearDown(provider.dispose);

      await _settleAsync();

      expect(provider.sources.map((source) => source.bookSourceUrl), [
        'source://one',
      ]);
      expect(fakeSourceDao.getDiscoveryPartCallCount, 0);
    },
  );

  test('filters out imported unsupported discovery sources', () async {
    fakeSourceDao.sources = [
      BookSource(
        bookSourceUrl: 'source://novel',
        bookSourceName: '小說源',
        enabled: true,
        enabledExplore: true,
        exploreUrl: '最新::https://example.com/novel',
      ),
      BookSource(
        bookSourceUrl: 'source://audio',
        bookSourceName: '有聲源',
        bookSourceType: 1,
        enabled: true,
        enabledExplore: true,
        exploreUrl: '最新::https://example.com/audio',
      )..addGroup(nonNovelSourceGroupTag),
    ];

    final provider = ExploreProvider(
      sourceDao: fakeSourceDao,
      kindsLoader: (exploreUrl, {source}) async => const [],
    );
    addTearDown(provider.dispose);

    await _settleAsync();

    expect(provider.sources.map((source) => source.bookSourceUrl), [
      'source://novel',
    ]);
  });
}
