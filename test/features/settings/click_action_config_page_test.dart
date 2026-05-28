import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:reader/core/constant/prefer_key.dart';
import 'package:reader/features/settings/click_action_config_page.dart';

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
  });
}
