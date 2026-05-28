import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader/core/database/dao/book_source_dao.dart';
import 'package:reader/core/models/book_source.dart';
import 'package:reader/core/models/source/explore_kind.dart';
import 'package:reader/features/explore/explore_provider.dart';

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
