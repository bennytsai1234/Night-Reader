import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/shared/widgets/app_state_view.dart';

void main() {
  testWidgets('renders hierarchy and invokes both actions', (tester) async {
    var primaryPressed = false;
    var secondaryPressed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppStateView(
            icon: Icons.search_off,
            title: '找不到相關書籍',
            description: '調整搜尋條件後再試一次。',
            primaryAction: AppStateAction(
              label: '清除條件',
              icon: Icons.clear,
              onPressed: () => primaryPressed = true,
            ),
            secondaryAction: AppStateAction(
              label: '重新整理',
              icon: Icons.refresh,
              onPressed: () => secondaryPressed = true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('找不到相關書籍'), findsOneWidget);
    expect(find.text('調整搜尋條件後再試一次。'), findsOneWidget);
    expect(find.byType(OutlinedButton), findsOneWidget);
    expect(find.byType(TextButton), findsOneWidget);

    await tester.tap(find.text('清除條件'));
    await tester.tap(find.text('重新整理'));
    expect(primaryPressed, isTrue);
    expect(secondaryPressed, isTrue);
  });

  testWidgets('supports large text in a short viewport without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: const Scaffold(
          body: AppStateView(
            icon: Icons.error_outline,
            title: '目前範圍沒有可搜尋的書源',
            description: '切換搜尋範圍，或到書源管理調整書源。',
            tone: AppStateTone.error,
            primaryAction: AppStateAction(
              label: '重新整理',
              icon: Icons.refresh,
              onPressed: null,
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });
}
