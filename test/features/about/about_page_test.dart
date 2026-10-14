import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/config/app_config.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/features/about/about_page.dart';
import 'package:night_reader/features/settings/settings_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    GetIt.instance.registerSingleton<SharedPreferences>(
      await SharedPreferences.getInstance(),
    );
    PackageInfo.setMockInitialValues(
      appName: '夜讀',
      packageName: 'com.inkpage.reader',
      version: '0.4.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  tearDown(() async {
    await GetIt.instance.reset();
    AppConfig.autoRefresh = true;
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => SettingsProvider(),
        child: const MaterialApp(home: AboutPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the Wi-Fi download row only shows while auto-check is on', (
    tester,
  ) async {
    await pumpPage(tester);

    expect(find.text('在 Wi-Fi 下自動下載更新'), findsOneWidget);

    await tester.ensureVisible(find.text('自動檢查更新'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('自動檢查更新'));
    await tester.pumpAndSettle();

    expect(find.text('在 Wi-Fi 下自動下載更新'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('update.auto_check'), isFalse);
  });

  testWidgets('system tools turn the launch shelf check off', (tester) async {
    await pumpPage(tester);

    await tester.ensureVisible(find.text('啟動時檢查書架更新'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('啟動時檢查書架更新'));
    await tester.pumpAndSettle();

    expect(AppConfig.autoRefresh, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(PreferKey.autoRefresh), isFalse);
  });
}
