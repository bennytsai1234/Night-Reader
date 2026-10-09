import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/source/explore_kind.dart';
import 'package:night_reader/features/explore/explore_page.dart';
import 'package:night_reader/features/explore/explore_provider.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:provider/provider.dart';

class _FakeSourceDao extends Fake implements BookSourceDao {
  _FakeSourceDao(this.sources);

  final List<BookSource> sources;

  @override
  Stream<List<BookSource>> watchDiscoveryPart() => Stream.value(sources);
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
}
