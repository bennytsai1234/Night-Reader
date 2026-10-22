import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_menu_entrance.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';

void main() {
  const menu = Key('menu');
  late ValueNotifier<bool> visibility;
  late int childBuilds;

  setUp(() {
    visibility = ValueNotifier(false);
    childBuilds = 0;
  });
  tearDown(() => visibility.dispose());

  /// 選單開關只改 [visibility]，外層不重建。
  Future<void> pumpEntrance(
    WidgetTester tester, {
    required bool visible,
    Duration delay = Duration.zero,
  }) async {
    if (find.byType(ReaderV2MenuEntrance).evaluate().isEmpty) {
      visibility.value = visible;
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topCenter,
            child: ReaderV2MenuEntrance(
              visible: visibility,
              edge: AxisDirection.up,
              delay: delay,
              child: Builder(
                builder: (context) {
                  childBuilds += 1;
                  return const SizedBox(key: menu, width: 100, height: 50);
                },
              ),
            ),
          ),
        ),
      );
      return;
    }
    visibility.value = visible;
    await tester.pump();
  }

  double topOf(WidgetTester tester) => tester.getTopLeft(find.byKey(menu)).dy;

  /// 收起時移開自身高度，再加上陰影伸出的距離。
  const hiddenTop = -50 - AppGlass.shadowReach;

  bool painted(WidgetTester tester) => tester
      .widget<Visibility>(
        find.ancestor(of: find.byKey(menu), matching: find.byType(Visibility)),
      )
      .visible;

  testWidgets('slides in over readerMenuIn without fading', (tester) async {
    await pumpEntrance(tester, visible: false);
    expect(topOf(tester), hiddenTop);
    expect(painted(tester), isFalse);

    await pumpEntrance(tester, visible: true);
    await tester.pump(AppMotion.readerMenuIn ~/ 2);
    expect(topOf(tester), inExclusiveRange(hiddenTop, 0));
    expect(painted(tester), isTrue);
    for (final fade in [Opacity, FadeTransition]) {
      expect(
        find.descendant(
          of: find.byType(ReaderV2MenuEntrance),
          matching: find.byType(fade),
        ),
        findsNothing,
      );
    }

    await tester.pumpAndSettle();
    expect(topOf(tester), 0);
  });

  testWidgets('opening and closing only moves the piece, never rebuilds it', (
    tester,
  ) async {
    await pumpEntrance(tester, visible: false);
    expect(childBuilds, 1);
    for (final visible in [true, false, true]) {
      await pumpEntrance(tester, visible: visible);
      await tester.pumpAndSettle();
    }
    expect(topOf(tester), 0);
    expect(childBuilds, 1);
  });

  testWidgets('a delayed piece waits before it starts moving', (tester) async {
    await pumpEntrance(
      tester,
      visible: false,
      delay: AppMotion.readerMenuStagger,
    );
    await pumpEntrance(
      tester,
      visible: true,
      delay: AppMotion.readerMenuStagger,
    );
    await tester.pump(AppMotion.readerMenuStagger ~/ 2);
    expect(topOf(tester), hiddenTop);

    await tester.pumpAndSettle();
    expect(topOf(tester), 0);
  });

  testWidgets('hides faster than it enters and ignores taps', (tester) async {
    await pumpEntrance(tester, visible: true);
    await pumpEntrance(tester, visible: false);
    // Exits accelerate: slow at first, fastest at the end.
    await tester.pump(AppMotion.readerMenuOut ~/ 2);
    expect(
      topOf(tester),
      closeTo(hiddenTop * Curves.easeInCubic.transform(0.5), 0.01),
    );
    await tester.pump(AppMotion.readerMenuOut ~/ 2);
    expect(topOf(tester), hiddenTop);
    expect(painted(tester), isFalse);
    expect(
      tester
          .widget<IgnorePointer>(
            find
                .ancestor(
                  of: find.byKey(menu),
                  matching: find.byType(IgnorePointer),
                )
                .first,
          )
          .ignoring,
      isTrue,
    );
  });
}
