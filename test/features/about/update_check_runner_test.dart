import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/services/app_update_installer.dart';
import 'package:night_reader/core/services/update_preferences.dart';
import 'package:night_reader/core/services/update_service.dart';
import 'package:night_reader/features/about/update_check_runner.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _info = UpdateInfo(
  versionName: '0.4.0',
  tagName: 'v0.4.0',
  updateLog: '',
  downloadUrl: 'https://example.com/night-reader.apk',
  assetSize: 1024,
  releasePageUrl: 'https://example.com/release',
);

class _FakeService extends AppUpdateService {
  _FakeService() : super(dio: Dio(), currentVersionLoader: () async => '0.3.0');

  int checks = 0;

  @override
  Future<UpdateInfo?> checkLatest({bool includeBeta = false}) async {
    checks++;
    return _info;
  }
}

class _FakeInstaller extends AppUpdateInstaller {
  _FakeInstaller({this.unmetered = true, this.failDownload = false})
    : super(dio: Dio());

  final bool unmetered;
  final bool failDownload;
  final downloaded = <String>[];
  int clears = 0;

  @override
  Future<bool> isOnUnmeteredNetwork() async => unmetered;

  @override
  Future<File> download(
    UpdateInfo info, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    downloaded.add(info.tagName);
    if (failDownload) throw StateError('offline');
    return File('night-reader-${info.tagName}.apk');
  }

  @override
  Future<void> install(File apk) async {}

  @override
  Future<void> clearDownloads() async => clears++;
}

void main() {
  late DateTime now;
  late UpdatePreferences preferences;
  late _FakeService service;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    now = DateTime(2026, 10, 13, 9);
    preferences = UpdatePreferences(clock: () => now);
    service = _FakeService();
  });

  /// 跑一次自動檢查並停在跳出的視窗（若有）；`done` 在視窗關閉、檢查結束時完成。
  Future<({Future<void> done})> startAutomatic(
    WidgetTester tester,
    AppUpdateInstaller installer,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    final runner = UpdateCheckRunner(
      service: service,
      preferences: preferences,
      installer: installer,
      isAndroid: () => true,
    );
    final run = runner.runAutomatic(() => context);
    await tester.pumpAndSettle();
    return (done: run);
  }

  testWidgets('turning off the automatic check skips it entirely', (
    tester,
  ) async {
    await preferences.setAutoCheck(false);
    final installer = _FakeInstaller();

    await (await startAutomatic(tester, installer)).done;

    expect(service.checks, 0);
    expect(installer.downloaded, isEmpty);
    expect(find.text('發現新版 0.4.0'), findsNothing);
  });

  testWidgets('on an unmetered network the dialog opens ready to install', (
    tester,
  ) async {
    final installer = _FakeInstaller();

    final run = await startAutomatic(tester, installer);

    expect(installer.downloaded, ['v0.4.0']);
    expect(find.text('新版已下載完成，可直接安裝。'), findsOneWidget);
    expect(find.text('安裝'), findsOneWidget);
    expect(find.text('立即更新'), findsNothing);

    await tester.tap(find.text('忽略此版'));
    await tester.pumpAndSettle();
    await run.done;
    expect(await preferences.isIgnored('v0.4.0'), isTrue);
    // 忽略的這版不會再裝，背景下載好的 APK 一併清掉。
    expect(installer.clears, 1);
  });

  testWidgets('a metered network leaves the download to the user', (
    tester,
  ) async {
    final installer = _FakeInstaller(unmetered: false);

    await startAutomatic(tester, installer);

    expect(installer.downloaded, isEmpty);
    expect(find.text('立即更新'), findsOneWidget);
  });

  testWidgets('the Wi-Fi download switch off leaves the download to the user', (
    tester,
  ) async {
    await preferences.setAutoDownload(false);
    final installer = _FakeInstaller();

    await startAutomatic(tester, installer);

    expect(installer.downloaded, isEmpty);
    expect(find.text('立即更新'), findsOneWidget);
  });

  testWidgets('a failed background download still shows the dialog', (
    tester,
  ) async {
    final installer = _FakeInstaller(failDownload: true);

    await startAutomatic(tester, installer);

    expect(installer.downloaded, ['v0.4.0']);
    expect(find.text('立即更新'), findsOneWidget);
  });

  testWidgets('remind later holds off automatic prompts for a week', (
    tester,
  ) async {
    final installer = _FakeInstaller(unmetered: false);

    final run = await startAutomatic(tester, installer);
    await tester.tap(find.text('稍後提醒'));
    await tester.pumpAndSettle();
    await run.done;

    now = now.add(const Duration(days: 6));
    await (await startAutomatic(tester, installer)).done;
    expect(find.text('發現新版 0.4.0'), findsNothing);

    now = now.add(const Duration(days: 1));
    await startAutomatic(tester, installer);
    expect(find.text('發現新版 0.4.0'), findsOneWidget);
  });

  testWidgets('an ignored version is neither downloaded nor shown', (
    tester,
  ) async {
    await preferences.ignore('v0.4.0');
    final installer = _FakeInstaller();

    await (await startAutomatic(tester, installer)).done;

    expect(installer.downloaded, isEmpty);
    expect(find.text('發現新版 0.4.0'), findsNothing);
  });

  testWidgets('a manual check ignores the remind-later cooldown', (
    tester,
  ) async {
    await preferences.remindLater();
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    final runner = UpdateCheckRunner(
      service: service,
      preferences: preferences,
      installer: _FakeInstaller(),
      isAndroid: () => true,
    );

    unawaited(runner.runManual(context));
    await tester.pumpAndSettle();

    expect(find.text('發現新版 0.4.0'), findsOneWidget);
  });
}
