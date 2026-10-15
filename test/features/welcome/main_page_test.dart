import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/welcome/main_page.dart';
import 'package:night_reader/shared/navigation/app_page_transition.dart';
import 'package:night_reader/shared/theme/app_style.dart';
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

  group('tapping a tab', () {
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
          ),
        ],
      ),
    );

    testWidgets('plays the chosen transition without passing the middle tab', (
      tester,
    ) async {
      await tester.pumpWidget(threeTabs());
      await tester.pumpAndSettle();

      await tester.tap(find.text('三'));
      await tester.pump();
      // 換頁前的畫面是快照，新分頁已經到位；中間的分頁沒有出現。
      expect(find.byType(AppTransitionSwitch), findsOneWidget);
      expect(find.byType(RawImage), findsOneWidget);
      expect(find.text('丙0'), findsOneWidget);
      expect(find.text('乙0'), findsNothing);

      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('乙0'), findsNothing);

      await tester.pumpAndSettle();
      expect(find.byType(AppTransitionSwitch), findsNothing);
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

    testWidgets('switches at once when animations are off', (tester) async {
      await tester.pumpWidget(threeTabs(disableAnimations: true));
      await tester.pumpAndSettle();

      await tester.tap(find.text('三'));
      await tester.pump();
      expect(find.byType(AppTransitionSwitch), findsNothing);
      expect(find.text('丙0'), findsOneWidget);
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
