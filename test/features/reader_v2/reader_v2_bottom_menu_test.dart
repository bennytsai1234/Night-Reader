import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_bottom_menu.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_menu_controller.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/glass.dart';

void main() {
  Future<ReaderV2MenuController> pumpMenu(WidgetTester tester) async {
    final menu = ReaderV2MenuController()..onScrubEnd(70);
    addTearDown(menu.dispose);
    void noop() {}
    void noopPercent(double _) {}
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ReaderV2BottomMenu(
              controlsVisible: true,
              navigation: ReaderV2ChapterNavigationState(
                chapterCount: 3,
                currentIndex: 1,
                scrub: menu.scrub,
                titleFor: (_) => '',
              ),
              isAutoPaging: false,
              dayNightIcon: Icons.dark_mode_rounded,
              dayNightTooltip: '切換深色模式',
              onOpenDrawer: noop,
              onTts: noop,
              onTimedTts: noop,
              onInterface: noop,
              onSettings: noop,
              onAutoPage: noop,
              onToggleDayNight: noop,
              onReplaceRule: noop,
              onPrevChapter: noop,
              onNextChapter: noop,
              onScrubStart: noopPercent,
              onScrubbing: noopPercent,
              onScrubEnd: noopPercent,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return menu;
  }

  double labelOpacity(WidgetTester tester) => tester
      .widget<AnimatedOpacity>(
        find.ancestor(
          of: find.text('本章 7/10'),
          matching: find.byType(AnimatedOpacity),
        ),
      )
      .opacity;

  double shownOpacity(WidgetTester tester) => tester
      .renderObject<RenderAnimatedOpacity>(
        find.ancestor(
          of: find.text('本章 7/10'),
          matching: find.byType(AnimatedOpacity),
        ),
      )
      .opacity
      .value;

  testWidgets('dragging the slider shows its label without moving the panel', (
    tester,
  ) async {
    final menu = await pumpMenu(tester);
    Rect panel() => tester.getRect(find.byType(GlassSurface).last);
    Rect button() => tester.getRect(find.byTooltip('切換深色模式'));
    Rect slider() => tester.getRect(find.byType(Slider));
    final restPanel = panel();
    final restButton = button();
    final restSlider = slider();
    expect(labelOpacity(tester), 0);

    menu.onScrubStart(70);
    await tester.pump();
    await tester.pump(AppMotion.fade ~/ 2);
    expect(shownOpacity(tester), inExclusiveRange(0, 1));
    expect(panel(), restPanel);
    expect(button(), restButton);
    expect(slider(), restSlider);

    await tester.pumpAndSettle();
    expect(shownOpacity(tester), 1);
    expect(panel(), restPanel);
    // 字在膠囊上緣與圓鈕之間，不蓋到圓鈕。
    final label = tester.getRect(find.text('本章 7/10'));
    expect(label.top, greaterThanOrEqualTo(restPanel.top));
    expect(label.bottom, lessThanOrEqualTo(restSlider.center.dy - 13));

    // 放開時淡出，留著最後的數字，版面一樣不動。
    menu.onScrubEnd(70);
    await tester.pump();
    await tester.pump(AppMotion.fade ~/ 2);
    expect(shownOpacity(tester), inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    expect(shownOpacity(tester), 0);
    expect(panel(), restPanel);
    expect(button(), restButton);
  });
}
