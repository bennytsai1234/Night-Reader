import 'dart:io';

import 'package:flutter/material.dart';
import 'package:reader/core/services/app_log_service.dart';
import 'package:reader/core/services/update_ignore_store.dart';
import 'package:reader/core/services/update_service.dart';
import 'package:reader/features/about/update_dialog.dart';

/// 自動 / 手動 更新檢查的入口。集中處理「呼叫 service → 看忽略 → 顯示 Dialog → 寫忽略」。
class UpdateCheckRunner {
  UpdateCheckRunner({AppUpdateService? service, UpdateIgnoreStore? ignoreStore})
    : _service = service ?? AppUpdateService(),
      _ignoreStore = ignoreStore ?? UpdateIgnoreStore();

  final AppUpdateService _service;
  final UpdateIgnoreStore _ignoreStore;

  /// 啟動時的背景檢查。對忽略過的版本會直接 return；非 Android 直接 return。
  ///
  /// 拿到的 `contextProvider` 是延遲取 context，避免 caller 持有不安全的 BuildContext。
  Future<void> runAutomatic(BuildContext? Function() contextProvider) async {
    if (!Platform.isAndroid) return;
    final info = await _service.checkLatest();
    if (info == null) return;
    if (await _ignoreStore.isIgnored(info.tagName)) return;
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
      final info = await _service.checkLatest();
      if (info == null) return UpdateCheckOutcome.upToDate;
      if (!context.mounted) return UpdateCheckOutcome.dismissed;
      await _showDialog(context, info);
      return UpdateCheckOutcome.shown;
    } catch (e, stack) {
      AppLog.e('Manual update check failed: $e', error: e, stackTrace: stack);
      return UpdateCheckOutcome.failed;
    }
  }

  Future<void> _showDialog(BuildContext context, UpdateInfo info) async {
    final result = await showDialog<UpdateDialogResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => UpdateDialog(info: info),
    );
    if (result == UpdateDialogResult.ignored) {
      await _ignoreStore.ignore(info.tagName);
    }
  }
}

enum UpdateCheckOutcome { shown, upToDate, failed, dismissed, notSupported }
