import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/app_lock/app_lock.dart';
import 'package:night_reader/core/config/app_config.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/features/about/about_page.dart';
import 'package:night_reader/features/settings/settings_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeLockPlatform implements AppLockPlatform {
  final List<AppLockAuthResult> results = [];
  int prompts = 0;

  @override
  Future<bool> supported() async => true;

  @override
  Future<AppLockAuthResult> authenticate() async {
    prompts++;
    return results.isEmpty ? AppLockAuthResult.failed : results.removeAt(0);
  }

  @override
  Future<String?> leaveReason() async => 'away';

  @override
  Future<void> markOwnExcursion() async {}

  @override
  Future<void> clearOwnExcursion() async {}

  @override
  Future<void> configure({required bool cover, required bool locked}) async {}

  @override
  Future<void> uncover() async {}
}

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

  Future<AppLock> startLock(
    WidgetTester tester, {
    AppLockMode mode = AppLockMode.off,
    bool cover = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PreferKey.appLockMode, mode.name);
    await prefs.setBool(PreferKey.appCoverOnLeave, cover);
    final platform = _FakeLockPlatform()
      ..results.addAll([AppLockAuthResult.passed, AppLockAuthResult.passed]);
    final lock = AppLock(platform: platform);
    lock.start(prefs);
    addTearDown(lock.dispose);
    return lock;
  }

  Future<void> pumpPage(WidgetTester tester, {AppLock? lock}) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => SettingsProvider(),
        child: MaterialApp(home: AboutPage(appLock: lock)),
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

  testWidgets(
    'privacy, permissions, the leave behaviour and clearing web data live here',
    (tester) async {
      final lock = await startLock(tester);
      await pumpPage(tester, lock: lock);
      for (final title in ['隱私說明', '權限', '離開時', '清除網頁資料']) {
        await tester.ensureVisible(find.text(title));
        expect(find.text(title), findsOneWidget, reason: title);
      }
    },
  );

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

  testWidgets('old cover and lock values show the matching leave option', (
    tester,
  ) async {
    for (final (mode, cover, label) in [
      (AppLockMode.off, false, '不蓋'),
      (AppLockMode.off, true, '蓋住畫面'),
      (AppLockMode.onLeave, false, '蓋住並解鎖才能打開'),
      (AppLockMode.onLeave, true, '蓋住並解鎖才能打開'),
      (AppLockMode.afterFiveMinutes, false, '蓋住，離開 5 分鐘後要解鎖'),
      (AppLockMode.afterFiveMinutes, true, '蓋住，離開 5 分鐘後要解鎖'),
    ]) {
      final lock = await startLock(tester, mode: mode, cover: cover);
      await pumpPage(tester, lock: lock);
      expect(find.text('離開時'), findsOneWidget);
      expect(find.text(label), findsOneWidget, reason: '$mode $cover');
      await tester.pumpWidget(const SizedBox.shrink());
      lock.dispose();
    }
  });

  testWidgets('the four leave options write the two stored values', (
    tester,
  ) async {
    final lock = await startLock(tester);
    await pumpPage(tester, lock: lock);
    final prefs = await SharedPreferences.getInstance();

    Future<void> pick(String label) async {
      await tester.tap(find.text('離開時'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    await pick('蓋住畫面');
    expect(prefs.getBool(PreferKey.appCoverOnLeave), isTrue);
    expect(prefs.getString(PreferKey.appLockMode), AppLockMode.off.name);

    await pick('蓋住並解鎖才能打開');
    expect(prefs.getBool(PreferKey.appCoverOnLeave), isTrue);
    expect(prefs.getString(PreferKey.appLockMode), AppLockMode.onLeave.name);

    await pick('蓋住，離開 5 分鐘後要解鎖');
    expect(prefs.getBool(PreferKey.appCoverOnLeave), isTrue);
    expect(
      prefs.getString(PreferKey.appLockMode),
      AppLockMode.afterFiveMinutes.name,
    );

    await pick('不蓋');
    expect(prefs.getBool(PreferKey.appCoverOnLeave), isFalse);
    expect(prefs.getString(PreferKey.appLockMode), AppLockMode.off.name);
    expect(find.text('不蓋'), findsOneWidget);
  });
}
