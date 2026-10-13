import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/welcome/main_page.dart';
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
          hidesTabBarOnScroll: true,
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

  testWidgets('scrolling down hides the tab bar and its fade; up brings them '
      'back', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(tabBarHidden(tester), isFalse);
    expect(fade(tester).hidden, isFalse);

    await tester.drag(find.text('甲3'), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(tabBarHidden(tester), isTrue);
    expect(fade(tester).hidden, isTrue);

    await tester.drag(find.text('甲10'), const Offset(0, 100));
    await tester.pumpAndSettle();
    expect(tabBarHidden(tester), isFalse);
    expect(fade(tester).hidden, isFalse);
  });

  testWidgets('a short scroll near the top keeps the tab bar', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    // 還沒捲過大標題的高度。
    await tester.drag(find.text('甲3'), const Offset(0, -30));
    await tester.pumpAndSettle();
    expect(tabBarHidden(tester), isFalse);
  });

  testWidgets('a hidden tab bar still lets pages swipe and comes back on the '
      'next page', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.drag(find.text('甲3'), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(tabBarHidden(tester), isTrue);

    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('乙0'), findsOneWidget);
    expect(tabBarHidden(tester), isFalse);
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
}
