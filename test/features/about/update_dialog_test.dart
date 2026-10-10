import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/services/app_update_installer.dart';
import 'package:night_reader/core/services/update_service.dart';
import 'package:night_reader/features/about/update_dialog.dart';

class _FakeInstaller extends AppUpdateInstaller {
  _FakeInstaller({this.failDownload = false}) : super(dio: Dio());

  final bool failDownload;
  final installed = <File>[];

  @override
  Future<File> download(
    UpdateInfo info, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    if (failDownload) throw StateError('offline');
    onProgress?.call(info.assetSize, info.assetSize);
    return File('night-reader-${info.tagName}.apk');
  }

  @override
  Future<void> install(File apk) async => installed.add(apk);
}

const _info = UpdateInfo(
  versionName: '0.4.0',
  tagName: 'v0.4.0',
  updateLog: '* fix(reader): something by @someone in https://x/pull/1',
  downloadUrl: 'https://example.com/night-reader.apk',
  assetSize: 1024,
  releasePageUrl: 'https://example.com/release',
);

Future<void> _pumpDialog(WidgetTester tester, AppUpdateInstaller installer) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: UpdateDialog(info: _info, installer: installer),
      ),
    ),
  );
}

void main() {
  testWidgets('立即更新 downloads in the app and opens the installer', (
    tester,
  ) async {
    final installer = _FakeInstaller();
    await _pumpDialog(tester, installer);

    expect(find.text('發現新版 0.4.0'), findsOneWidget);
    expect(find.text('• fix(reader): something'), findsOneWidget);

    await tester.tap(find.text('立即更新'));
    await tester.pumpAndSettle();

    expect(installer.installed.single.path, 'night-reader-v0.4.0.apk');
    expect(find.text('下載完成，請在系統畫面確認安裝。'), findsOneWidget);

    // 在系統安裝畫面取消後回來，可以再按一次安裝。
    await tester.tap(find.text('安裝'));
    await tester.pumpAndSettle();
    expect(installer.installed, hasLength(2));
  });

  testWidgets('a failed download offers retry and the release page', (
    tester,
  ) async {
    await _pumpDialog(tester, _FakeInstaller(failDownload: true));

    await tester.tap(find.text('立即更新'));
    await tester.pumpAndSettle();

    expect(find.text('下載失敗，請重試或改到下載頁下載。'), findsOneWidget);
    expect(find.text('重試'), findsOneWidget);
    expect(find.text('前往下載頁'), findsOneWidget);
  });
}
