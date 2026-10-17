import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/source/explore_kind.dart';
import 'package:night_reader/features/explore/explore_page.dart';
import 'package:night_reader/features/explore/explore_provider.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/group_filter_bar.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSourceDao extends Fake implements BookSourceDao {
  _FakeSourceDao(List<BookSource> sources) : _sources = Stream.value(sources);

  _FakeSourceDao.stream(this._sources);

  final Stream<List<BookSource>> _sources;

  @override
  Stream<List<BookSource>> watchDiscoveryPart() => _sources;

  bool hasAny = true;

  /// 有值時改由它決定有沒有書源，用來觀察還不知道的那段時間。
  Stream<bool>? hasAnyStream;

  @override
  Stream<bool> watchHasAny() => hasAnyStream ?? Stream.value(hasAny);
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    getIt.registerSingleton<SharedPreferences>(
      await SharedPreferences.getInstance(),
    );
  });

  tearDown(() => getIt.unregister<SharedPreferences>());

  testWidgets('expanding the next source without collapsing keeps it in view', (
    tester,
  ) async {
    final sources = [
      for (var i = 0; i < 30; i++)
        BookSource(
          bookSourceUrl: 'https://s$i.example',
          bookSourceName: '書源$i',
          exploreUrl: 'https://s$i.example/explore',
          customOrder: i,
        ),
    ];
    final provider = ExploreProvider(
      sourceDao: _FakeSourceDao(sources),
      // 足夠多的分類，讓展開區高過半個畫面。
      kindsLoader: (_, {source}) async => [
        for (var i = 0; i < 40; i++)
          ExploreKind(title: '分類$i', url: 'https://k$i.example'),
      ],
    );
    addTearDown(provider.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<ExploreProvider>.value(
        value: provider,
        child: MaterialApp(
          theme: buildAppTheme(AppStyle.paper, Brightness.dark),
          home: const ExplorePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final headerBottom = tester.getBottomLeft(find.byType(GlassNavHeader)).dy;
    Future<void> expectRowBelowHeader(String name) async {
      final top = tester.getTopLeft(find.text(name)).dy;
      expect(top, greaterThanOrEqualTo(headerBottom - 1), reason: name);
      expect(
        top,
        lessThan(
          tester.view.physicalSize.height / tester.view.devicePixelRatio,
        ),
        reason: name,
      );
    }

    await tester.tap(find.text('書源2'));
    await tester.pumpAndSettle();
    await expectRowBelowHeader('書源2');

    // 不收起書源2，直接展開下方的書源3。
    await tester.tap(find.text('書源3'));
    await tester.pumpAndSettle();
    await expectRowBelowHeader('書源3');
    expect(find.text('分類0'), findsOneWidget);
  });

  testWidgets('sources show a skeleton while loading and fade in after', (
    tester,
  ) async {
    final sources = StreamController<List<BookSource>>();
    addTearDown(sources.close);
    final provider = ExploreProvider(
      sourceDao: _FakeSourceDao.stream(sources.stream),
      kindsLoader: (_, {source}) async => const [],
    );
    addTearDown(provider.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<ExploreProvider>.value(
        value: provider,
        child: MaterialApp(
          theme: buildAppTheme(AppStyle.paper, Brightness.light),
          home: const ExplorePage(),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(SkeletonLine), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    sources.add([
      BookSource(
        bookSourceUrl: 'https://s.example',
        bookSourceName: '書源甲',
        exploreUrl: 'https://s.example/explore',
      ),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('書源甲'), findsOneWidget);
    expect(find.byType(SkeletonLine), findsNothing);
  });

  for (final hasAny in [false, true]) {
    testWidgets(
      hasAny
          ? 'sources without explore point to the source manager'
          : 'with no source at all the empty page offers an import',
      (tester) async {
        final dao = _FakeSourceDao(const [])..hasAny = hasAny;
        getIt.registerSingleton<BookSourceDao>(dao);
        addTearDown(() => getIt.unregister<BookSourceDao>());
        final provider = ExploreProvider(
          sourceDao: dao,
          kindsLoader: (_, {source}) async => const [],
        );
        addTearDown(provider.dispose);

        await tester.pumpWidget(
          ChangeNotifierProvider<ExploreProvider>.value(
            value: provider,
            child: MaterialApp(
              theme: buildAppTheme(AppStyle.paper, Brightness.light),
              home: const ExplorePage(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('匯入書源'), hasAny ? findsNothing : findsOneWidget);
        expect(
          find.text('目前沒有可用的發現書源'),
          hasAny ? findsOneWidget : findsNothing,
        );
      },
    );
  }

  Future<ExploreProvider> pumpExplore(
    WidgetTester tester,
    _FakeSourceDao dao, {
    List<ExploreKind> kinds = const [],
  }) async {
    final provider = ExploreProvider(
      sourceDao: dao,
      kindsLoader: (_, {source}) async => kinds,
    );
    addTearDown(provider.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<ExploreProvider>.value(
        value: provider,
        child: MaterialApp(
          theme: buildAppTheme(AppStyle.paper, Brightness.light),
          home: const ExplorePage(),
        ),
      ),
    );
    return provider;
  }

  List<BookSource> groupedSources() => [
    for (var i = 0; i < 3; i++)
      BookSource(
        bookSourceUrl: 'https://s$i.example',
        bookSourceName: '書源$i',
        bookSourceGroup: '甲',
        exploreUrl: 'https://s$i.example/explore',
        customOrder: i,
      ),
  ];

  double headerHeight(WidgetTester tester) =>
      tester.getSize(find.byType(GlassNavHeader)).height;

  group('group filter row', () {
    testWidgets('is in place from the first frame when groups were seen', (
      tester,
    ) async {
      await getIt<SharedPreferences>().setString(
        'explore_filter_bar',
        '{"all": 3, "groups": [["甲", 3]]}',
      );
      final sources = StreamController<List<BookSource>>();
      addTearDown(sources.close);
      await pumpExplore(tester, _FakeSourceDao.stream(sources.stream));
      await tester.pump();

      expect(find.byType(GroupFilterBar<String?>), findsOneWidget);
      final before = headerHeight(tester);
      final skeletonTop = tester
          .getTopLeft(find.byType(GroupedSliceItem).first)
          .dy;

      sources.add(groupedSources());
      await tester.pump();
      // 換場第一幀：清單與淡出中的骨架都沒被往下推。
      expect(headerHeight(tester), before);
      expect(
        tester.getTopLeft(find.byType(GroupedSliceItem).first).dy,
        skeletonTop,
      );
      await tester.pumpAndSettle();
      expect(headerHeight(tester), before);
    });

    testWidgets('grows in when the record had no groups', (tester) async {
      final sources = StreamController<List<BookSource>>();
      addTearDown(sources.close);
      await pumpExplore(tester, _FakeSourceDao.stream(sources.stream));
      await tester.pump();
      expect(find.byType(GroupFilterBar<String?>), findsNothing);
      final before = headerHeight(tester);

      sources.add(groupedSources());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final mid = headerHeight(tester);
      await tester.pumpAndSettle();
      final after = headerHeight(tester);

      expect(mid, greaterThan(before));
      expect(mid, lessThan(after));
      // 記下這次的分組，下次開 App 從第一幀就留好。
      expect(
        getIt<SharedPreferences>().getString('explore_filter_bar'),
        '{"all":3,"groups":[["甲",3]]}',
      );
    });
  });

  testWidgets('collapsing keeps the categories until the last frame', (
    tester,
  ) async {
    await pumpExplore(
      tester,
      _FakeSourceDao(groupedSources()),
      kinds: [
        for (var i = 0; i < 6; i++)
          ExploreKind(title: '分類$i', url: 'https://k$i.example'),
      ],
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('書源0'));
    await tester.pumpAndSettle();
    final chip = find.text('分類0');
    expect(chip, findsOneWidget);
    final rowBelow = tester.getTopLeft(find.text('書源1')).dy;

    await tester.tap(find.text('書源0'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    // 收合途中分類還在，跟著淡出；下一列連續往上收。
    expect(chip, findsOneWidget);
    final opacity = tester
        .widget<FadeTransition>(
          find.ancestor(of: chip, matching: find.byType(FadeTransition)).first,
        )
        .opacity
        .value;
    expect(opacity, greaterThan(0));
    expect(opacity, lessThan(1));
    final midBelow = tester.getTopLeft(find.text('書源1')).dy;
    expect(midBelow, lessThan(rowBelow));

    await tester.pumpAndSettle();
    expect(chip, findsNothing);
    expect(tester.getTopLeft(find.text('書源1')).dy, lessThan(midBelow));
  });

  testWidgets('the empty page waits to know whether any source exists', (
    tester,
  ) async {
    final hasAny = StreamController<bool>();
    addTearDown(hasAny.close);
    final dao = _FakeSourceDao(const [])..hasAnyStream = hasAny.stream;
    getIt.registerSingleton<BookSourceDao>(dao);
    addTearDown(() => getIt.unregister<BookSourceDao>());
    await pumpExplore(tester, dao);
    await tester.pumpAndSettle();

    expect(find.text('匯入書源'), findsNothing);
    expect(find.text('目前沒有可用的發現書源'), findsNothing);

    hasAny.add(false);
    // 第一幀收到事件、開始淡入，再過一段才量。
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final opacity = tester
        .widget<FadeTransition>(
          find
              .ancestor(
                of: find.text('還沒有書源'),
                matching: find.byType(FadeTransition),
              )
              .first,
        )
        .opacity
        .value;
    expect(opacity, greaterThan(0));
    expect(opacity, lessThan(1));
    await tester.pumpAndSettle();
    expect(find.text('匯入書源'), findsOneWidget);
    expect(find.text('目前沒有可用的發現書源'), findsNothing);
  });
}
