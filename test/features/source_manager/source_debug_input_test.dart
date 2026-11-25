import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/models/source/explore_kind.dart';
import 'package:night_reader/features/source_manager/source_debug_page.dart';
import 'package:night_reader/features/source_manager/widgets/source_manager_dialogs.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';

import '../../test_helper.dart';

/// 除錯前問關鍵字，同 Legado `BookSourceDebugActivity`：預先填校驗關鍵字，
/// 校驗關鍵字與第一個發現分類點了就用它除錯。
void main() {
  setupTestDI();

  final pushed = <Route<dynamic>>[];

  Future<void> open(
    WidgetTester tester,
    BookSource source, {
    List<ExploreKind> kinds = const [],
  }) async {
    pushed.clear();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        navigatorObservers: [_Pushes(pushed)],
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => SourceManagerDialogs.showDebugInput(
                context,
                source,
                loadExploreKinds: (_) async => kinds,
              ),
              child: const Text('除錯'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('除錯'));
    await tester.pumpAndSettle();
  }

  /// 點了之後推入的除錯頁用的關鍵字；不讓它真的開始除錯。
  String? pushedKey(WidgetTester tester) {
    final route = pushed.whereType<MaterialPageRoute<dynamic>>().lastOrNull;
    if (route == null) return null;
    final page = route.builder(tester.element(find.byType(Scaffold).first));
    return (page as SourceDebugPage).debugKey;
  }

  BookSource source({String? checkKey, String? exploreUrl}) => BookSource(
    bookSourceUrl: 'https://debug.test',
    bookSourceName: '除錯',
    exploreUrl: exploreUrl,
    ruleSearch: SearchRule(checkKeyWord: checkKey),
  );

  testWidgets('without a check keyword the field starts with 我的世界', (
    tester,
  ) async {
    await open(tester, source());
    expect(find.widgetWithText(TextField, '我的世界'), findsOneWidget);
  });

  testWidgets('the check keyword fills the field and starts debugging', (
    tester,
  ) async {
    await open(tester, source(checkKey: '斗羅'));
    expect(find.widgetWithText(TextField, '斗羅'), findsOneWidget);

    await tester.tap(find.widgetWithText(GestureDetector, '斗羅').last);
    await tester.pump();
    expect(pushedKey(tester), '斗羅');
  });

  testWidgets('the first explore category debugs from discovery', (
    tester,
  ) async {
    await open(
      tester,
      source(exploreUrl: '/x'),
      kinds: const [
        ExploreKind(title: '分類'),
        ExploreKind(title: '玄幻', url: '/x/1'),
        ExploreKind(title: '武俠', url: '/x/2'),
      ],
    );
    expect(find.text('武俠'), findsNothing);

    await tester.tap(find.text('玄幻'));
    await tester.pump();
    expect(pushedKey(tester), '玄幻::/x/1');
  });

  testWidgets('a broken explore rule shows no category', (tester) async {
    await open(
      tester,
      source(exploreUrl: '<js>throw 1</js>'),
      kinds: const [ExploreKind(title: 'ERROR:壞了', url: '壞了')],
    );
    expect(find.textContaining('ERROR'), findsNothing);
  });
}

class _Pushes extends NavigatorObserver {
  _Pushes(this.pushed);

  final List<Route<dynamic>> pushed;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is MaterialPageRoute) pushed.add(route);
  }
}
