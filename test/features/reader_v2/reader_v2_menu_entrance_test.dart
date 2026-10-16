import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/services/motion_gate.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_menu_entrance.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';

void main() {
  Future<void> pumpEntrance(
    WidgetTester tester, {
    required bool visible,
    Duration delay = Duration.zero,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: ReaderV2MenuEntrance(
            visible: visible,
            hiddenOffset: const Offset(0, -1.3),
            delay: delay,
            child: const SizedBox(key: Key('menu'), width: 100, height: 50),
          ),
        ),
      ),
    );
  }

  double opacityOf(WidgetTester tester) => tester
      .widget<FadeTransition>(
        find
            .ancestor(
              of: find.byKey(const Key('menu')),
              matching: find.byType(FadeTransition),
            )
            .first,
      )
      .opacity
      .value;

  Offset slideOf(WidgetTester tester) => tester
      .widget<SlideTransition>(
        find
            .ancestor(
              of: find.byKey(const Key('menu')),
              matching: find.byType(SlideTransition),
            )
            .first,
      )
      .position
      .value;

  testWidgets('slides and fades in over readerMenuIn, holding the gate', (
    tester,
  ) async {
    await pumpEntrance(tester, visible: false);
    expect(opacityOf(tester), 0);
    expect(slideOf(tester), const Offset(0, -1.3));

    await pumpEntrance(tester, visible: true);
    await tester.pump(AppMotion.readerMenuIn ~/ 2);
    expect(opacityOf(tester), inExclusiveRange(0, 1));
    expect(slideOf(tester).dy, inExclusiveRange(-1.3, 0));
    expect(MotionGate.instance.isMoving, isTrue);

    await tester.pumpAndSettle();
    expect(opacityOf(tester), 1);
    expect(slideOf(tester), Offset.zero);
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
    expect(opacityOf(tester), 0);

    await tester.pumpAndSettle();
    expect(opacityOf(tester), 1);
  });

  testWidgets('hides faster than it enters and ignores taps', (tester) async {
    await pumpEntrance(tester, visible: true);
    await pumpEntrance(tester, visible: false);
    await tester.pump(AppMotion.readerMenuOut);
    expect(opacityOf(tester), 0);
    expect(
      tester
          .widget<IgnorePointer>(
            find
                .ancestor(
                  of: find.byKey(const Key('menu')),
                  matching: find.byType(IgnorePointer),
                )
                .first,
          )
          .ignoring,
      isTrue,
    );
  });
}
