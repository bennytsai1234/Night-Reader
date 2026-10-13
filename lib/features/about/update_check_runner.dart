import 'dart:io';

import 'package:flutter/material.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/app_update_installer.dart';
import 'package:night_reader/core/services/update_preferences.dart';
import 'package:night_reader/core/services/update_service.dart';
import 'package:night_reader/features/about/update_dialog.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';

/// 自動 / 手動 更新檢查的入口。集中處理「呼叫 service → 看忽略與稍後提醒 →
/// 視網路先下載 → 顯示 Dialog → 寫忽略或稍後提醒」。
class UpdateCheckRunner {
  UpdateCheckRunner({
    AppUpdateService? service,
    UpdatePreferences? preferences,
    AppUpdateInstaller? installer,
    bool Function()? isAndroid,
  }) : _service = service ?? AppUpdateService(),
       _preferences = preferences ?? UpdatePreferences(),
       _installer = installer ?? AppUpdateInstaller(),
       _isAndroid = isAndroid ?? _isAndroidPlatform;

  final AppUpdateService _service;
  final UpdatePreferences _preferences;
  final AppUpdateInstaller _installer;
  final bool Function() _isAndroid;

  /// 啟動時的背景檢查。非 Android、關閉自動檢查時直接 return；
  /// 忽略過的版本、「稍後提醒」冷卻期內也不跳視窗。
  ///
  /// 不計流量的網路下會先在背景下載好 APK，視窗直接停在可安裝的狀態；
  /// 背景下載失敗就照原本流程跳視窗，讓使用者手動下載。
  ///
  /// 拿到的 `contextProvider` 是延遲取 context，避免 caller 持有不安全的 BuildContext。
  Future<void> runAutomatic(BuildContext? Function() contextProvider) async {
    if (!_isAndroid()) return;
    if (!await _preferences.autoCheck()) return;
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
    if (!await _shouldPrompt(info)) return;
    final apk = await _downloadInBackground(info);
    // 到視窗關掉之前，這份 APK 不能被其他清理（例如手動檢查得到已是最新版）刪掉。
    if (apk != null) _installer.hold(apk);
    final UpdateDialogResult? result;
    try {
      // 下載期間使用者可能已從手動檢查的視窗按了忽略或稍後提醒。
      if (!await _shouldPrompt(info)) return;
      final context = contextProvider();
      if (context == null || !context.mounted) return;
      result = await _showDialog(context, info, downloadedApk: apk);
    } finally {
      if (apk != null) _installer.release(apk);
    }
    await _applyResult(info, result);
  }

  Future<bool> _shouldPrompt(UpdateInfo info) async =>
      !await _preferences.isIgnored(info.tagName) &&
      !await _preferences.inRemindLaterCooldown();

  /// 手動觸發。會回 `UpdateCheckOutcome`，呼叫端可顯示 SnackBar 告知結果。
  Future<UpdateCheckOutcome> runManual(BuildContext context) async {
    if (!_isAndroid()) {
      return UpdateCheckOutcome.notSupported;
    }
    try {
      final info = await _check();
      if (info == null) {
        await _clearDownloads();
        return UpdateCheckOutcome.upToDate;
      }
      if (!context.mounted) return UpdateCheckOutcome.dismissed;
      await _applyResult(info, await _showDialog(context, info));
      return UpdateCheckOutcome.shown;
    } catch (e, stack) {
      AppLog.e('Manual update check failed: $e', error: e, stackTrace: stack);
      return UpdateCheckOutcome.failed;
    }
  }

  Future<UpdateInfo?> _check() async =>
      _service.checkLatest(includeBeta: await _preferences.betaChannel());

  /// 開啟「在 Wi-Fi 下自動下載更新」且目前網路不計流量時，先靜默下載 APK。
  /// 沒下載或下載失敗回 `null`；失敗只記 log，不打擾使用者。
  Future<File?> _downloadInBackground(UpdateInfo info) async {
    try {
      if (!await _preferences.autoDownload()) return null;
      if (!await _installer.isOnUnmeteredNetwork()) return null;
      return await _installer.download(info);
    } catch (e, stack) {
      AppLog.e(
        'Background update download failed: $e',
        error: e,
        stackTrace: stack,
      );
      return null;
    }
  }

  /// 已經開著更新視窗的 Navigator。背景檢查與手動檢查各自建立 runner，
  /// 兩邊同時找到新版時靠這裡只跳一個視窗。
  static final _dialogOpen = Expando<bool>();

  /// 跳出更新視窗，回傳使用者的選擇；已有視窗開著時不跳，回 `null`。
  Future<UpdateDialogResult?> _showDialog(
    BuildContext context,
    UpdateInfo info, {
    File? downloadedApk,
  }) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    if (_dialogOpen[navigator] ?? false) return null;
    _dialogOpen[navigator] = true;
    try {
      return await showDialog<UpdateDialogResult>(
        context: context,
        barrierDismissible: false,
        barrierColor: AppChrome.of(context).barrier,
        builder: (_) => UpdateDialog(
          info: info,
          installer: _installer,
          downloadedApk: downloadedApk,
        ),
      );
    } finally {
      _dialogOpen[navigator] = null;
    }
  }

  Future<void> _applyResult(UpdateInfo info, UpdateDialogResult? result) async {
    switch (result) {
      case UpdateDialogResult.ignored:
        await _preferences.ignore(info.tagName);
        // 背景先下載好的這版不會再裝，不必留著佔空間。
        await _clearDownloads();
      case UpdateDialogResult.later:
        await _preferences.remindLater();
      case null:
        break;
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

bool _isAndroidPlatform() => Platform.isAndroid;

enum UpdateCheckOutcome { shown, upToDate, failed, dismissed, notSupported }
