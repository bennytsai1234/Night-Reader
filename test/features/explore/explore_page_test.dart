import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/source/explore_kind.dart';
import 'package:night_reader/features/explore/explore_page.dart';
import 'package:night_reader/features/explore/explore_provider.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';
import 'package:provider/provider.dart';

class _FakeSourceDao extends Fake implements BookSourceDao {
  _FakeSourceDao(List<BookSource> sources) : _sources = Stream.value(sources);

  _FakeSourceDao.stream(this._sources);

  final Stream<List<BookSource>> _sources;

  @override
  Stream<List<BookSource>> watchDiscoveryPart() => _sources;
}

void main() {
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

    // 頁首佔用的高度固定，捲動後大標題收合，看得到的頁首是漸隱底板那一段。
    final headerBackdrop = find.descendant(
      of: find.byType(GlassNavHeader),
      matching: find.byType(EdgeFade),
    );
    Future<void> expectRowBelowHeader(String name) async {
      final headerBottom = tester.getBottomLeft(headerBackdrop).dy;
      final top = tester.getTopLeft(find.text(name)).dy;
      expect(top, greaterThanOrEqualTo(headerBottom - 1), reason: name);
      // 貼著收合後的頁首，不留下一個大標題高的空白。
      expect(
        top,
        lessThan(headerBottom + AppGlass.largeTitleHeight),
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
}
