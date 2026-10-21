import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/app_dialogs.dart';
import 'package:night_reader/shared/widgets/floating_tab_bar.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/glass_menu.dart';

import '../../support/glass_motion.dart';

// 玻璃的進出場只滑動或由玻璃自己淡，動畫途中模糊一直取得到底下的畫面，
// 最後一幀就是靜止時的樣子（ADR 0022）。

void main() {
  // 同一份主題：每次重建都算一份新的話，MaterialApp 會把兩份當成不同
  // （`AppPageTransitionsBuilder` 沒有 `==`）而播主題漸變。
  final theme = buildAppTheme(AppStyle.paper, Brightness.light);
  Widget app(Widget home) => MaterialApp(theme: theme, home: home);

  /// 每一塊玻璃此刻的模糊強度。
  List<String> blursOf(WidgetTester tester) => [
    for (final filter in tester.widgetList<BackdropFilter>(
      find.byType(BackdropFilter),
    ))
      filter.filter.toString(),
  ];

  testWidgets('the check catches glass wrapped in a fade', (tester) async {
    await tester.pumpWidget(
      app(
        const Center(
          child: Opacity(
            opacity: 0.5,
            child: GlassSurface(child: SizedBox(width: 80, height: 40)),
          ),
        ),
      ),
    );
    expect(() => expectNoGlassUnderFade(tester), throwsA(isA<TestFailure>()));
  });

  testWidgets('the check catches glass in a fading sliver', (tester) async {
    await tester.pumpWidget(
      app(
        const CustomScrollView(
          slivers: [
            SliverOpacity(
              opacity: 0.5,
              sliver: SliverToBoxAdapter(
                child: GlassSurface(child: SizedBox(width: 80, height: 40)),
              ),
            ),
          ],
        ),
      ),
    );
    expect(() => expectNoGlassUnderFade(tester), throwsA(isA<TestFailure>()));
  });

  group('GlassSlide', () {
    const box = Key('box');

    Future<void> pumpSlide(WidgetTester tester, double shown) =>
        tester.pumpWidget(
          app(
            Align(
              alignment: Alignment.bottomLeft,
              child: GlassSlide(
                shown: shown,
                edge: AxisDirection.down,
                gap: 10,
                child: const SizedBox(key: box, width: 80, height: 40),
              ),
            ),
          ),
        );

    testWidgets('hidden means past the edge, gap and shadow, and not drawn', (
      tester,
    ) async {
      await pumpSlide(tester, 1);
      final rest = tester.getTopLeft(find.byKey(box)).dy;

      await pumpSlide(tester, 0.5);
      expect(
        tester.getTopLeft(find.byKey(box)).dy - rest,
        (40 + 10 + AppGlass.shadowReach) / 2,
      );

      await pumpSlide(tester, 0);
      expect(
        tester.getTopLeft(find.byKey(box)).dy - rest,
        40 + 10 + AppGlass.shadowReach,
      );
      expect(
        tester
            .widget<Visibility>(
              find.ancestor(
                of: find.byKey(box),
                matching: find.byType(Visibility),
              ),
            )
            .visible,
        isFalse,
      );
    });

    // 閱讀器的上下選單收起時還在元件樹裡：開書時「上一章／下一章」從停用
    // 變成可按，按鈕的主題與字色漸變原本在畫面外每格重算一次，剛好落在
    // 開書的換頁動畫裡。
    testWidgets('hidden content does not animate and is at rest once shown', (
      tester,
    ) async {
      const enabled = Color(0xFF102030);
      Future<void> pumpButton(double shown, {required bool canPress}) =>
          tester.pumpWidget(
            app(
              Align(
                alignment: Alignment.bottomLeft,
                child: GlassSlide(
                  shown: shown,
                  edge: AxisDirection.down,
                  child: TextButton(
                    onPressed: canPress ? () {} : null,
                    style: TextButton.styleFrom(
                      foregroundColor: enabled,
                      disabledForegroundColor: const Color(0xFF999999),
                    ),
                    child: const Text('下一章'),
                  ),
                ),
              ),
            ),
          );
      Color? labelColor() => tester
          .widget<RichText>(
            find.descendant(
              of: find.text('下一章'),
              matching: find.byType(RichText),
            ),
          )
          .text
          .style
          ?.color;

      await pumpButton(0, canPress: false);
      await pumpButton(0, canPress: true);
      // 沒有動畫在等下一格。
      expect(tester.binding.transientCallbackCount, 0);

      bool drawn() => tester
          .widget<Visibility>(
            find.ancestor(
              of: find.text('下一章'),
              matching: find.byType(Visibility),
            ),
          )
          .visible;

      // 系統關閉動畫時選單直接到位：畫出來的每一格都是可按的顏色，不先
      // 露出一格停用色。
      await tester.pump(const Duration(milliseconds: 500));
      await pumpButton(1, canPress: true);
      if (drawn()) expect(labelColor(), enabled);
      await tester.pump(const Duration(milliseconds: 16));
      expect(drawn(), isTrue);
      expect(labelColor(), enabled);
    });
  });

  testWidgets('a revealed glass fades its blur too and ends as plain glass', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const Center(
          child: GlassSurface(child: SizedBox(width: 80, height: 40)),
        ),
      ),
    );
    final resting = blursOf(tester);

    final controller = AnimationController(
      vsync: tester,
      duration: const Duration(milliseconds: 100),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      app(
        Center(
          child: GlassReveal(
            animation: controller,
            child: const GlassSurface(child: SizedBox(width: 80, height: 40)),
          ),
        ),
      ),
    );
    controller.value = 0.5;
    await tester.pump();
    expectNoGlassUnderFade(tester);
    expect(blursOf(tester), isNot(resting));

    controller.value = 1;
    await tester.pump();
    expect(blursOf(tester), resting);
  });

  testWidgets('an alert only fades, with its blur fading along', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showAppAlert<void>(
              context: context,
              title: '標題',
              actions: const [AppAlertAction<void>(label: '好', value: null)],
            ),
            child: const Text('開'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('開'));
    await tester.pump();
    await tester.pump(AppMotion.menu ~/ 2);
    expectNoGlassUnderFade(tester);
    final rect = tester.getRect(find.text('標題'));

    await tester.pumpAndSettle();
    // 不縮放：從頭到尾都在同一個位置、同一個大小。
    expect(tester.getRect(find.text('標題')), rect);
  });

  testWidgets('a glass menu grows from its anchor without fading', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => Align(
            alignment: Alignment.topLeft,
            child: TextButton(
              onPressed: () => showGlassMenu<String>(
                context: context,
                anchor: const Rect.fromLTWH(20, 20, 44, 44),
                entries: const [GlassMenuItem(value: 'a', label: '項目')],
              ),
              child: const Text('開'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('開'));
    await tester.pump();
    final menu = find.ancestor(
      of: find.text('項目'),
      matching: find.byType(ScaleTransition),
    );
    expect(tester.widget<ScaleTransition>(menu).scale.value, 0);

    await tester.pump(AppMotion.menu ~/ 2);
    expect(tester.widget<ScaleTransition>(menu).scale.value, greaterThan(0));
    expectNoGlassUnderFade(tester);

    await tester.pumpAndSettle();
    expect(tester.widget<ScaleTransition>(menu).scale.value, 1);
  });

  testWidgets('the long-press preview blur fades by its strength', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showContextPreviewMenu<String>(
              context: context,
              sourceRect: const Rect.fromLTWH(40, 40, 100, 140),
              preview: const ColoredBox(color: Colors.brown),
              entries: const [GlassMenuItem(value: 'a', label: '項目')],
            ),
            child: const Text('長按'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('長按'));
    await tester.pump();
    await tester.pump(AppMotion.menu ~/ 2);
    expectNoGlassUnderFade(tester);
  });

  testWidgets('the floating tab bar sinks away without fading', (tester) async {
    Future<void> pumpBar({required bool hidden}) => tester.pumpWidget(
      app(
        Scaffold(
          bottomNavigationBar: FloatingTabBar(
            items: const [
              FloatingTabItem(
                icon: Icons.book,
                selectedIcon: Icons.book,
                label: '書架',
              ),
              FloatingTabItem(
                icon: Icons.explore,
                selectedIcon: Icons.explore,
                label: '發現',
              ),
            ],
            currentIndex: 0,
            onTap: (_) {},
            hidden: hidden,
          ),
        ),
      ),
    );
    await pumpBar(hidden: false);
    await pumpBar(hidden: true);
    await tester.pump(AppMotion.menu ~/ 2);
    expectNoGlassUnderFade(tester);
  });
}
