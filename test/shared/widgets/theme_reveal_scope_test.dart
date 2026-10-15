import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/theme_reveal_scope.dart';

void main() {
  /// 和 App 一樣把 [ThemeRevealScope] 掛在 MaterialApp.builder；按鈕切換深淺。
  Widget app({required ThemeMode mode, required VoidCallback onToggle}) {
    return MaterialApp(
      theme: ThemeData(brightness: Brightness.light),
      darkTheme: ThemeData(brightness: Brightness.dark),
      themeMode: mode,
      themeAnimationStyle: AnimationStyle.noAnimation,
      builder: (context, child) => ThemeRevealScope(child: child!),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () =>
                  ThemeRevealScope.of(context).run(change: onToggle),
              child: Text(Theme.of(context).brightness.name),
            ),
          ),
        ),
      ),
    );
  }

  /// 轉場時蓋在畫面上的舊畫面擷取圖（不攔點擊的那一層）。
  Finder overlay() => find.descendant(
    of: find.byType(ThemeRevealScope),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is CustomPaint &&
          widget.painter.runtimeType.toString() == '_InkRevealPainter',
    ),
  );

  Future<void> pumpToggleApp(WidgetTester tester) {
    var mode = ThemeMode.light;
    return tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => app(
          mode: mode,
          onToggle: () => setState(() {
            mode = mode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
          }),
        ),
      ),
    );
  }

  testWidgets('切換後新主題立即生效，墨暈結束後移除蓋圖', (tester) async {
    await pumpToggleApp(tester);
    expect(find.text('light'), findsOneWidget);
    expect(overlay(), findsNothing);

    await tester.tap(find.byType(TextButton));
    await tester.pump();

    // 底下已經是新主題，舊畫面的擷取圖蓋在上面準備暈開。
    expect(find.text('dark'), findsOneWidget);
    expect(overlay(), findsOneWidget);

    await tester.pump(AppMotion.themeReveal ~/ 2);
    expect(overlay(), findsOneWidget);

    // 圓從換色那一幀畫完才開始計時，多等一幀才播完。
    await tester.pump(AppMotion.themeReveal);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump();
    expect(overlay(), findsNothing);
    expect(find.text('dark'), findsOneWidget);
  });

  testWidgets('轉場中照常可以點擊，再切一次接著暈開', (tester) async {
    await pumpToggleApp(tester);

    await tester.tap(find.byType(TextButton));
    await tester.pump(AppMotion.themeReveal ~/ 3);
    await tester.tap(find.byType(TextButton));
    await tester.pump();

    expect(find.text('light'), findsOneWidget);
    expect(overlay(), findsOneWidget);

    await tester.pumpAndSettle();
    expect(overlay(), findsNothing);
  });

  testWidgets('關閉系統動畫時直接換色，不蓋擷取圖', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpToggleApp(tester);

    await tester.tap(find.byType(TextButton));
    await tester.pump();

    expect(find.text('dark'), findsOneWidget);
    expect(overlay(), findsNothing);
  });

  testWidgets('不在 ThemeRevealScope 之下時直接執行變更', (tester) async {
    var changed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                ThemeRevealScope.of(context).run(change: () => changed = true),
            child: const Text('切換'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('切換'));
    expect(changed, isTrue);
  });
}
