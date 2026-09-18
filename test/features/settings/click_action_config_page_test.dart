import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/features/settings/click_action_config_page.dart';
import 'package:night_reader/shared/theme/app_theme.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('ClickActionConfigPage reset persists all-menu defaults', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ClickActionConfigPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('恢復預設'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(PreferKey.readerClickActions), '0,0,0,0,0,0,0,0,0');
    expect(find.text('已恢復預設設定'), findsOneWidget);
  });

  testWidgets('ClickActionConfigPage persists updated actions', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ClickActionConfigPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('區域 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一頁'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(PreferKey.readerClickActions), '1,0,0,0,0,0,0,0,0');
    expect(find.text('已儲存點擊區域設定'), findsOneWidget);
  });

  for (final mode in <ThemeMode>[ThemeMode.light, ThemeMode.dark]) {
    testWidgets('reset action inherits the $mode theme foreground', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: mode,
          home: const ClickActionConfigPage(),
        ),
      );
      await tester.pumpAndSettle();

      final label = tester.widget<Text>(find.text('恢復預設'));
      expect(label.style?.color, isNull);
      expect(find.text('點擊區域設定'), findsOneWidget);
    });
  }
}
