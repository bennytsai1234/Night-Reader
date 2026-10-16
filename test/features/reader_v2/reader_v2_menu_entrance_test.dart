import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/services/motion_gate.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_menu_entrance.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';

void main() {
  const menu = Key('menu');

  Future<void> pumpEntrance(
    WidgetTester tester, {
    required bool visible,
    Duration delay = Duration.zero,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topCenter,
          child: ReaderV2MenuEntrance(
            visible: visible,
            edge: AxisDirection.up,
            delay: delay,
            child: const SizedBox(key: menu, width: 100, height: 50),
          ),
        ),
      ),
    );
  }

  double topOf(WidgetTester tester) => tester.getTopLeft(find.byKey(menu)).dy;

  /// 收起時移開自身高度，再加上陰影伸出的距離。
  const hiddenTop = -50 - AppGlass.shadowReach;

  bool painted(WidgetTester tester) => tester
      .widget<Visibility>(
        find.ancestor(of: find.byKey(menu), matching: find.byType(Visibility)),
      )
      .visible;

  testWidgets('slides in over readerMenuIn without fading, holding the gate', (
    tester,
  ) async {
    await pumpEntrance(tester, visible: false);
    expect(topOf(tester), hiddenTop);
    expect(painted(tester), isFalse);

    await pumpEntrance(tester, visible: true);
    await tester.pump(AppMotion.readerMenuIn ~/ 2);
    expect(topOf(tester), inExclusiveRange(hiddenTop, 0));
    expect(painted(tester), isTrue);
    expect(MotionGate.instance.isMoving, isTrue);
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
    expect(MotionGate.instance.isMoving, isFalse);
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
