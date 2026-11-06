import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/welcome/main_page.dart';
import 'package:night_reader/shared/navigation/app_page_transition.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/floating_tab_bar.dart';

const _firstBackground = Color(0xFFEEDDCC);
const _secondBackground = Color(0xFF223344);

Color _first(BuildContext _) => _firstBackground;
Color _second(BuildContext _) => _secondBackground;

class _ListPage extends StatelessWidget {
  const _ListPage(this.name, this.background);

  final String name;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      body: ListView.builder(
        itemCount: 80,
        itemBuilder: (_, i) => SizedBox(height: 60, child: Text('$name$i')),
      ),
    );
  }
}

void main() {
  Widget app() => MaterialApp(
    theme: buildAppTheme(AppStyle.paper, Brightness.light),
    home: const MainPage(
      destinations: [
        MainDestination(
          icon: Icons.book_outlined,
          selectedIcon: Icons.book,
          label: '一',
          page: _ListPage('甲', _firstBackground),
          background: _first,
        ),
        MainDestination(
          icon: Icons.explore_outlined,
          selectedIcon: Icons.explore,
          label: '二',
          page: _ListPage('乙', _secondBackground),
          background: _second,
        ),
      ],
    ),
  );

  bool tabBarHidden(WidgetTester tester) =>
      tester.widget<FloatingTabBar>(find.byType(FloatingTabBar)).hidden;

  /// 正在播換頁：換頁前的畫面是一張快照。
  bool switching(WidgetTester tester) =>
      tester
          .widget<AppTransitionSwitch>(find.byType(AppTransitionSwitch))
          .outgoing !=
      null;
  FloatingTabBarFade fade(WidgetTester tester) =>
      tester.widget<FloatingTabBarFade>(find.byType(FloatingTabBarFade));

  testWidgets('scrolling never sinks the tab bar or its fade', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.drag(find.text('甲3'), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(tabBarHidden(tester), isFalse);
    expect(fade(tester).hidden, isFalse);
  });

  testWidgets('the fade takes the colour of the page being shown', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(fade(tester).color, _firstBackground);

    // 拖到一半：顏色在兩頁之間。
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PageView)),
    );
    await gesture.moveBy(const Offset(-100, 0));
    await gesture.moveBy(const Offset(-100, 0));
    await tester.pump();
    final between = fade(tester).color;
    expect(between, isNot(_firstBackground));
    expect(between, isNot(_secondBackground));

    // 測試畫面寬 800，拖過一半才會停在下一頁。
    await gesture.moveBy(const Offset(-400, 0));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(fade(tester).color, _secondBackground);
  });

  Widget threeTabs({bool disableAnimations = false}) => MaterialApp(
    theme: buildAppTheme(AppStyle.paper, Brightness.light),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(disableAnimations: disableAnimations),
      child: child!,
    ),
    home: const MainPage(
      destinations: [
        MainDestination(
          icon: Icons.book_outlined,
          selectedIcon: Icons.book,
          label: '一',
          page: _ListPage('甲', _firstBackground),
        ),
        MainDestination(
          icon: Icons.explore_outlined,
          selectedIcon: Icons.explore,
          label: '二',
          page: _ListPage('乙', _secondBackground),
        ),
        MainDestination(
          icon: Icons.person_outline,
          selectedIcon: Icons.person,
          label: '三',
          page: _ListPage('丙', _firstBackground),
          scrollsToTopWhenLeft: true,
        ),
      ],
    ),
  );

  group('tapping a tab', () {
    testWidgets('plays the chosen transition without passing the middle tab', (
      tester,
    ) async {
      await tester.pumpWidget(threeTabs());
      await tester.pumpAndSettle();

      await tester.tap(find.text('三'));
      await tester.pump();
      // 換頁前的畫面是快照，新分頁已經到位；中間的分頁沒有出現。
      expect(switching(tester), isTrue);
      expect(find.byType(RawImage), findsOneWidget);
      expect(find.text('丙0'), findsOneWidget);
      expect(find.text('乙0'), findsNothing);

      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('乙0'), findsNothing);

      await tester.pumpAndSettle();
      expect(switching(tester), isFalse);
      expect(find.byType(RawImage), findsNothing);
      expect(find.text('丙0'), findsOneWidget);
    });

    testWidgets('keeps each tab where it was scrolled', (tester) async {
      await tester.pumpWidget(threeTabs());
      await tester.pumpAndSettle();

      await tester.drag(find.text('甲3'), const Offset(0, -600));
      await tester.pumpAndSettle();
      await tester.tap(find.text('二'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('一'));
      await tester.pumpAndSettle();
      expect(find.text('甲0'), findsNothing);
    });

    testWidgets('tabs are not rebuilt when a switch starts or ends', (
      tester,
    ) async {
      var builds = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(AppStyle.paper, Brightness.light),
          home: MainPage(
            destinations: [
              MainDestination(
                icon: Icons.book_outlined,
                selectedIcon: Icons.book,
                label: '一',
                page: Builder(
                  builder: (context) {
                    builds++;
                    // 和真的分頁一樣依賴主題：被搬動時會跟著重建。
                    return ColoredBox(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      child: const Center(child: Text('甲')),
                    );
                  },
                ),
              ),
              const MainDestination(
                icon: Icons.explore_outlined,
                selectedIcon: Icons.explore,
                label: '二',
                page: _ListPage('乙', _secondBackground),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      final before = builds;

      await tester.tap(find.text('二'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('一'));
      await tester.pump();
      expect(switching(tester), isTrue);
      await tester.pumpAndSettle();

      expect(switching(tester), isFalse);
      expect(find.text('甲'), findsOneWidget);
      expect(builds, before);
    });

    int capsule(WidgetTester tester) =>
        tester.widget<FloatingTabBar>(find.byType(FloatingTabBar)).currentIndex;
    AppTransitionSwitch transition(WidgetTester tester) =>
        tester.widget<AppTransitionSwitch>(find.byType(AppTransitionSwitch));
    double left(WidgetTester tester) =>
        tester.getRect(find.byType(RawImage)).left;

    testWidgets('the capsule moves at once; the page rests only the first '
        'time a tab is shown', (tester) async {
      await tester.pumpWidget(threeTabs());
      await tester.pumpAndSettle();

      await tester.tap(find.text('三'));
      // 第一幀很重（拍快照、排新分頁）；第一次來到「三」時再停
      // [AppMotion.stillGap]，換頁前的畫面停在原處，膠囊不等、已經往「三」。
      await tester.pump();
      expect(capsule(tester), 2);
      await tester.pump(AppMotion.stillGap - const Duration(milliseconds: 10));
      expect(left(tester), 0);
      // 新分頁原樣畫在舊頁快照底下：字先上過螢幕。
      expect(tester.getRect(find.text('丙0')).left, greaterThanOrEqualTo(0));
      expect(
        tester.getRect(find.text('丙0')).right,
        lessThanOrEqualTo(tester.getSize(find.byType(MainPage)).width),
      );
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump(const Duration(milliseconds: 16));
      expect(left(tester), lessThan(0));
      expect(left(tester), greaterThan(-120));
      await tester.pumpAndSettle();
      expect(switching(tester), isFalse);

      // 回到畫過的「一」：畫完第一幀就開始換，不再停。
      await tester.tap(find.text('一'));
      await tester.pump();
      expect(capsule(tester), 0);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      expect(left(tester), greaterThan(0));
      await tester.pumpAndSettle();
      expect(switching(tester), isFalse);
    });

    testWidgets('a tap during a switch carries on from where the screen is', (
      tester,
    ) async {
      await tester.pumpWidget(threeTabs());
      await tester.pumpAndSettle();

      await tester.tap(find.text('三'));
      await tester.pump();
      await tester.pump(AppMotion.stillGap);
      await tester.pump(const Duration(milliseconds: 60));
      final trip = transition(tester).trip as int;
      expect(left(tester), lessThan(0));

      // 播到一半點「二」：換到一半的畫面拍成新一趟的舊頁，從原處接著換到
      // 「二」，不等這段播完、不跳到「三」；膠囊馬上往「二」。
      await tester.tap(find.text('二'));
      await tester.pump();
      expect(transition(tester).trip, trip + 1);
      expect(left(tester), 0);
      expect(capsule(tester), 1);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      expect(left(tester), isNot(0));

      await tester.pumpAndSettle();
      expect(transition(tester).trip, trip + 1);
      expect(switching(tester), isFalse);
      expect(find.text('乙0'), findsOneWidget);
      expect(capsule(tester), 1);
    });

    testWidgets('taps while a switch still rests only change where it goes', (
      tester,
    ) async {
      await tester.pumpWidget(threeTabs());
      await tester.pumpAndSettle();

      // 還停在起點時點「二」又點「三」：螢幕上一直是換頁前的畫面，最後換到
      // 「三」。
      await tester.tap(find.text('三'));
      await tester.pump();
      await tester.tap(find.text('二'));
      await tester.pump();
      expect(left(tester), 0);
      await tester.tap(find.text('三'));
      await tester.pump();
      expect(left(tester), 0);
      expect(capsule(tester), 2);

      await tester.pumpAndSettle();
      expect(switching(tester), isFalse);
      expect(find.text('丙0'), findsOneWidget);
    });

    testWidgets('tapping the tab a switch is going to changes nothing', (
      tester,
    ) async {
      await tester.pumpWidget(threeTabs());
      await tester.pumpAndSettle();

      await tester.tap(find.text('三'));
      await tester.pump();
      final trip = transition(tester).trip as int;
      await tester.tap(find.text('三'));
      await tester.pumpAndSettle();

      expect(transition(tester).trip, trip);
      expect(find.text('丙0'), findsOneWidget);
    });

    testWidgets('the back key while going back to the first tab goes there', (
      tester,
    ) async {
      await tester.pumpWidget(threeTabs());
      await tester.pumpAndSettle();
      await tester.tap(find.text('三'));
      await tester.pumpAndSettle();

      // 正在回「一」時點「二」、又按返回鍵：返回鍵也是回「一」，接著換回
      // 「一」，不跳「再按一次退出」。
      await tester.tap(find.text('一'));
      await tester.pump();
      await tester.tap(find.text('二'));
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('甲0'), findsOneWidget);
      expect(capsule(tester), 0);
      expect(find.text('再按一次退出'), findsNothing);
    });

    testWidgets('dragging the capsule switches as it crosses each tab', (
      tester,
    ) async {
      await tester.pumpWidget(threeTabs());
      await tester.pumpAndSettle();
      final from = tester.getCenter(find.text('一'));
      final middle = tester.getCenter(find.text('二'));
      final to = tester.getCenter(find.text('三'));

      // 手指還按著：跨進「二」就換到「二」，再跨進「三」就從畫面現在的樣子
      // 接著換到「三」。
      final gesture = await tester.startGesture(from);
      await gesture.moveTo(Offset.lerp(from, middle, 0.2)!);
      await tester.pump();
      await gesture.moveTo(middle);
      await tester.pump();
      expect(capsule(tester), 1);
      expect(switching(tester), isTrue);
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.moveTo(to);
      await tester.pump();
      expect(capsule(tester), 2);
      await tester.pumpAndSettle();
      expect(find.text('丙0'), findsOneWidget);

      // 放開時頁面已經在「三」，什麼都不再換。
      await gesture.up();
      await tester.pumpAndSettle();
      expect(switching(tester), isFalse);
      expect(capsule(tester), 2);
      expect(find.text('丙0'), findsOneWidget);
    });

    testWidgets('switches at once when animations are off', (tester) async {
      await tester.pumpWidget(threeTabs(disableAnimations: true));
      await tester.pumpAndSettle();

      await tester.tap(find.text('三'));
      await tester.pump();
      expect(switching(tester), isFalse);
      expect(find.text('丙0'), findsOneWidget);
    });
  });

  group('Android predictive back on another tab', () {
    Future<void> send(
      WidgetTester tester,
      String method, [
      Map<String, Object?>? arguments,
    ]) => tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      SystemChannels.backGesture.name,
      SystemChannels.backGesture.codec.encodeMethodCall(
        MethodCall(method, arguments),
      ),
      (_) {},
    );

    Map<String, Object?> event(double x, double progress) => {
      'touchOffset': [x, 300.0],
      'progress': progress,
      'swipeEdge': 0,
    };

    int selectedTab(WidgetTester tester) =>
        tester.widget<FloatingTabBar>(find.byType(FloatingTabBar)).currentIndex;

    Future<void> openThirdTab(WidgetTester tester) async {
      await tester.pumpWidget(threeTabs());
      await tester.pumpAndSettle();
      await tester.tap(find.text('三'));
      await tester.pumpAndSettle();
      await tester.drag(find.text('丙3'), const Offset(0, -600));
      await tester.pumpAndSettle();
    }

    testWidgets('the shelf comes back as far as the gesture goes', (
      tester,
    ) async {
      await openThirdTab(tester);
      await send(tester, 'startBackGesture', event(0, 0));
      await send(tester, 'updateBackGestureProgress', event(200, 0.5));
      // 進度照觸控重新取樣晚 38ms 才畫到（同一般頁面的預測返回）。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));

      // 預設的平移：這一頁的快照跟著進度往右移一半，底下露出書架。
      expect(switching(tester), isTrue);
      expect(tester.getRect(find.byType(RawImage)).left, closeTo(400, 1));
      expect(find.text('甲0'), findsOneWidget);
      expect(find.text('乙0'), findsNothing);
      // 還沒確定返回，膠囊留在原本的分頁。
      expect(selectedTab(tester), 2);

      await send(tester, 'commitBackGesture');
      await tester.pumpAndSettle();
      expect(switching(tester), isFalse);
      expect(selectedTab(tester), 0);
      expect(find.text('甲0'), findsOneWidget);
      expect(find.text('丙0'), findsNothing);
    });

    testWidgets('a cancelled gesture stays on the tab where it was', (
      tester,
    ) async {
      await openThirdTab(tester);
      await send(tester, 'startBackGesture', event(0, 0));
      await send(tester, 'updateBackGestureProgress', event(100, 0.3));
      await tester.pump();
      await send(tester, 'cancelBackGesture');
      await tester.pumpAndSettle();

      expect(switching(tester), isFalse);
      expect(selectedTab(tester), 2);
      // 捲動位置還在，沒有因為途中露出書架而捲回頂端。
      expect(find.text('丙0'), findsNothing);
      expect(find.text('丙10'), findsOneWidget);
    });

    testWidgets('removing the main page while a cancelled gesture springs '
        'back does not touch the removed tabs', (tester) async {
      await openThirdTab(tester);
      await send(tester, 'startBackGesture', event(0, 0));
      await send(tester, 'updateBackGestureProgress', event(100, 0.3));
      await tester.pump();
      await send(tester, 'cancelBackGesture');
      await tester.pump(const Duration(milliseconds: 16));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('after a gesture the main page is not rebuilt when a page is '
        'pushed over it or comes back', (tester) async {
      await openThirdTab(tester);
      // 開始手勢時要看主頁是不是最上層；看的方式不能讓主頁從此依賴路由狀態。
      await send(tester, 'startBackGesture', event(0, 0));
      await tester.pump();
      await send(tester, 'cancelBackGesture');
      await tester.pumpAndSettle();

      var builds = 0;
      debugOnRebuildDirtyWidget = (element, _) {
        if (element.widget is MainPage) builds++;
      };
      try {
        Navigator.push(
          tester.element(find.text('丙10')),
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('上面那頁')),
          ),
        );
        await tester.pumpAndSettle();
        Navigator.pop(tester.element(find.text('上面那頁')));
        await tester.pumpAndSettle();
      } finally {
        debugOnRebuildDirtyWidget = null;
      }
      expect(builds, 0);
    });

    testWidgets('on the shelf the gesture is left to the system', (
      tester,
    ) async {
      await tester.pumpWidget(threeTabs());
      await tester.pumpAndSettle();
      await send(tester, 'startBackGesture', event(0, 0));
      await send(tester, 'updateBackGestureProgress', event(100, 0.3));
      await tester.pump();
      expect(switching(tester), isFalse);
      await send(tester, 'cancelBackGesture');
      await tester.pumpAndSettle();
    });
  });

  testWidgets('a tab that scrolls to top when left starts at the top again', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: const MainPage(
          destinations: [
            MainDestination(
              icon: Icons.book_outlined,
              selectedIcon: Icons.book,
              label: '一',
              page: _ListPage('甲', _firstBackground),
            ),
            MainDestination(
              icon: Icons.person_outline,
              selectedIcon: Icons.person,
              label: '二',
              page: _ListPage('乙', _secondBackground),
              scrollsToTopWhenLeft: true,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> swipePage(double dx) async {
      await tester.fling(find.byType(PageView), Offset(dx, 0), 2000);
      await tester.pumpAndSettle();
    }

    // 第一頁沒有設定，捲動位置照舊保留。
    await tester.drag(find.text('甲3'), const Offset(0, -600));
    await tester.pumpAndSettle();
    await swipePage(-600);
    await tester.drag(find.text('乙3'), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.text('乙0'), findsNothing);

    await swipePage(600);
    expect(find.text('甲0'), findsNothing);

    await swipePage(-600);
    expect(find.text('乙0'), findsOneWidget);
  });
}
