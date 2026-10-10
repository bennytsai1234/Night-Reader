import 'dart:io';

import 'package:flutter/material.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/app_update_installer.dart';
import 'package:night_reader/core/services/update_preferences.dart';
import 'package:night_reader/core/services/update_service.dart';
import 'package:night_reader/features/about/update_dialog.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';

/// 自動 / 手動 更新檢查的入口。集中處理「呼叫 service → 看忽略 → 顯示 Dialog → 寫忽略」。
class UpdateCheckRunner {
  UpdateCheckRunner({
    AppUpdateService? service,
    UpdatePreferences? preferences,
    AppUpdateInstaller? installer,
  }) : _service = service ?? AppUpdateService(),
       _preferences = preferences ?? UpdatePreferences(),
       _installer = installer ?? AppUpdateInstaller();

  final AppUpdateService _service;
  final UpdatePreferences _preferences;
  final AppUpdateInstaller _installer;

  /// 啟動時的背景檢查。對忽略過的版本會直接 return；非 Android 直接 return。
  ///
  /// 拿到的 `contextProvider` 是延遲取 context，避免 caller 持有不安全的 BuildContext。
  Future<void> runAutomatic(BuildContext? Function() contextProvider) async {
    if (!Platform.isAndroid) return;
    final UpdateInfo? info;
    try {
      info = await _check();
    } catch (e, stack) {
      // 背景檢查失敗不打擾使用者，記錄即可。
      AppLog.e(
        'Automatic update check failed: $e',
        error: e,
        stackTrace: stack,
      );
      return;
    }
    if (info == null) {
      await _clearDownloads();
      return;
    }
    if (await _preferences.isIgnored(info.tagName)) return;
    final context = contextProvider();
    if (context == null || !context.mounted) return;
    await _showDialog(context, info);
  }

  /// 手動觸發。會回 `UpdateCheckOutcome`，呼叫端可顯示 SnackBar 告知結果。
  Future<UpdateCheckOutcome> runManual(BuildContext context) async {
    if (!Platform.isAndroid) {
      return UpdateCheckOutcome.notSupported;
    }
    try {
      final info = await _check();
      if (info == null) {
        await _clearDownloads();
        return UpdateCheckOutcome.upToDate;
      }
      if (!context.mounted) return UpdateCheckOutcome.dismissed;
      await _showDialog(context, info);
      return UpdateCheckOutcome.shown;
    } catch (e, stack) {
      AppLog.e('Manual update check failed: $e', error: e, stackTrace: stack);
      return UpdateCheckOutcome.failed;
    }
  }

  Future<UpdateInfo?> _check() async =>
      _service.checkLatest(includeBeta: await _preferences.betaChannel());

  Future<void> _showDialog(BuildContext context, UpdateInfo info) async {
    final result = await showDialog<UpdateDialogResult>(
      context: context,
      barrierDismissible: false,
      barrierColor: AppChrome.of(context).barrier,
      builder: (_) => UpdateDialog(info: info, installer: _installer),
    );
    if (result == UpdateDialogResult.ignored) {
      await _preferences.ignore(info.tagName);
    }
  }

  /// 已是最新版時，清掉更新後留下的安裝檔；清不掉不影響檢查結果。
  Future<void> _clearDownloads() async {
    try {
      await _installer.clearDownloads();
    } catch (e, stack) {
      AppLog.e(
        'Clearing update downloads failed: $e',
        error: e,
        stackTrace: stack,
      );
    }
  }
}

enum UpdateCheckOutcome { shown, upToDate, failed, dismissed, notSupported }
