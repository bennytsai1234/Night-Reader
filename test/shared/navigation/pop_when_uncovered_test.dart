// 閱讀器返回前先讓底下那頁在後面畫好（字的貼圖建在畫面靜止時），停
// AppMotion.stillGap 才開始返回動畫（ADR 0037 策略一）。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/shared/navigation/pop_when_uncovered.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';

class _Route extends MaterialPageRoute<void> with PopWhenUncovered<void> {
  _Route() : super(builder: (_) => const ColoredBox(color: Color(0xFF000000)));
}

void main() {
  testWidgets('the page below is painted before the pop animation starts', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigator, home: const Text('底下那頁')),
    );
    final route = _Route();
    navigator.currentState!.push(route);
    await tester.pumpAndSettle();
    // 蓋住時底下那頁不畫（offstage）。
    expect(find.text('底下那頁'), findsNothing);

    unawaited(route.popWhenUncovered());
    await tester.pump();
    // 底下那頁畫出來了，這一頁還整頁蓋著，返回動畫還沒開始。
    expect(find.text('底下那頁'), findsOneWidget);
    expect(route.animation!.status, AnimationStatus.completed);

    // 重複按返回只返回一次。
    unawaited(route.popWhenUncovered());
    await tester.pump();
    await tester.pump(AppMotion.stillGap - const Duration(milliseconds: 20));
    expect(route.animation!.status, AnimationStatus.completed);

    await tester.pump(const Duration(milliseconds: 40));
    await tester.pump();
    expect(route.animation!.status, AnimationStatus.reverse);
    await tester.pumpAndSettle();
    expect(route.isActive, isFalse);
    expect(find.text('底下那頁'), findsOneWidget);
  });
}
