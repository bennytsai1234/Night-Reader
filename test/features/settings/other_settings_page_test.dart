import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:reader/core/constant/prefer_key.dart';
import 'package:reader/features/settings/other_settings_page.dart';
import 'package:reader/features/settings/settings_provider.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    GetIt.instance.registerSingleton<SharedPreferences>(
      await SharedPreferences.getInstance(),
    );
  });

  tearDown(() async => GetIt.instance.reset());

  testWidgets('OtherSettingsPage uses reader prefs for showAddToShelfAlert', (
    tester,
  ) async {
    // Override initial values and re-register so SettingsProvider sees them.
    SharedPreferences.setMockInitialValues({
      PreferKey.showAddToShelfAlert: false,
    });
    GetIt.instance.unregister<SharedPreferences>();
    GetIt.instance.registerSingleton<SharedPreferences>(
      await SharedPreferences.getInstance(),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => SettingsProvider(),
        child: const MaterialApp(home: OtherSettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile).last).value,
      isFalse,
    );

    await tester.tap(find.text('顯示加入書架提示'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(PreferKey.showAddToShelfAlert), isTrue);
  });
}
