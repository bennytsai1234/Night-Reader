import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/launch_entrance.dart';

void main() {
  Widget host() => MaterialApp(
    theme: buildAppTheme(AppStyle.paper, Brightness.light),
    home: LaunchEntrance(
      child: Scaffold(
        appBar: GlassNavHeader(
          title: '書架',
          leading: GlassIconButton(icon: Icons.menu, onPressed: () {}),
        ),
      ),
    ),
  );

  double buttonShown(WidgetTester tester) => tester
      .widget<GlassSlide>(
        find.ancestor(
          of: find.byType(GlassIconButton),
          matching: find.byType(GlassSlide),
        ),
      )
      .shown;

  /// 標題外面所有淡入淡出相乘的濃度（標題自己也有一層顯示與否的淡入）。
  double titleOpacity(WidgetTester tester) => tester
      .widgetList<FadeTransition>(
        find.ancestor(
          of: find.text('書架'),
          matching: find.byType(FadeTransition),
        ),
      )
      .fold(1.0, (opacity, fade) => opacity * fade.opacity.value);

  testWidgets('the first frame is only the background, then chrome enters', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    expect(buttonShown(tester), 0, reason: '和系統啟動畫面一樣只有底色');
    expect(titleOpacity(tester), 0);

    await tester.pump();
    await tester.pump(LaunchEntrance.chrome ~/ 2);
    expect(buttonShown(tester), inExclusiveRange(0, 1), reason: '玻璃按鈕滑進來');

    await tester.pumpAndSettle();
    expect(buttonShown(tester), 1);
    expect(titleOpacity(tester), 1);
  });

  test('the whole entrance ends with the later of chrome and skeleton', () {
    expect(
      LaunchEntranceMotion.totalFor(const Duration(milliseconds: 600)),
      LaunchEntrance.skeletonDelay + const Duration(milliseconds: 600),
    );
    expect(
      LaunchEntranceMotion.totalFor(const Duration(milliseconds: 100)),
      LaunchEntrance.tabBarDelay + LaunchEntrance.chrome,
    );
  });
}
