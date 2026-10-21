import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/settings/settings_provider.dart';
import 'package:night_reader/features/settings/theme_settings_provider.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:provider/provider.dart';

import '../../support/app_harness.dart';
import '../../support/navigation_budget.dart';

void main() {
  testWidgets('一般設定通知不重建 App，深淺、語言與外觀仍會更新', (tester) async {
    setUpPhone(tester);
    await tester.runAsync(setUpApp);
    await pumpApp(tester);
    await rest(tester);
    final root = find.byType(MaterialApp);
    final context = tester.element(root);
    final settings = context.read<SettingsProvider>();
    final themeSettings = context.read<ThemeSettingsProvider>();
    final original = tester.widget<MaterialApp>(root);

    // 走真正的設定寫入與通知：原本 Consumer2 收到任何通知都新建 MaterialApp。
    settings.setAutoRefresh(!settings.autoRefresh);
    await tester.pump();
    final afterRefresh = tester.widget<MaterialApp>(root);
    settings.setReplaceEnableDefault(!settings.replaceEnableDefault);
    await tester.pump();
    final afterReplace = tester.widget<MaterialApp>(root);

    settings.setThemeMode(ThemeMode.dark);
    await tester.pump();
    final changedMode = tester.widget<MaterialApp>(root).themeMode;
    settings.locale = const Locale('en');
    settings.update();
    await tester.pump();
    final changedLocale = tester.widget<MaterialApp>(root).locale;

    themeSettings.setStyle(AppStyle.values.last);
    await tester.pump();
    final changed = tester.widget<MaterialApp>(root);
    await tearDownApp(tester);

    expect(afterRefresh, same(original));
    expect(afterReplace, same(original));
    expect(changedMode, ThemeMode.dark);
    expect(changedLocale, const Locale('en'));
    expect(changed.theme, isNot(original.theme));
    expect(changed.darkTheme, isNot(original.darkTheme));
  });
}
