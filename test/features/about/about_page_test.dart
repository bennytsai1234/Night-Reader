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

  testWidgets('one row picks manual, auto-check or Wi-Fi download', (
    tester,
  ) async {
    await pumpPage(tester);
    final prefs = await SharedPreferences.getInstance();

    // 預設自動檢查、Wi-Fi 下自動下載（UpdatePreferences 的預設）。
    await tester.ensureVisible(find.text('自動更新'));
    await tester.pumpAndSettle();
    expect(find.text('Wi-Fi 下自動下載'), findsOneWidget);

    await tester.tap(find.text('自動更新'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('不自動').last);
    await tester.pumpAndSettle();
    expect(prefs.getBool('update.auto_check'), isFalse);

    await tester.tap(find.text('自動更新'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('自動檢查').last);
    await tester.pumpAndSettle();
    expect(prefs.getBool('update.auto_check'), isTrue);
    expect(prefs.getBool('update.auto_download_unmetered'), isFalse);
  });

  testWidgets('privacy, permissions and clearing web data live here', (
    tester,
  ) async {
    await pumpPage(tester);
    for (final title in ['隱私說明', '權限', '清除網頁資料']) {
      await tester.ensureVisible(find.text(title));
      expect(find.text(title), findsOneWidget, reason: title);
    }
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
