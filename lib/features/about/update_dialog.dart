import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/app_update_installer.dart';
import 'package:night_reader/core/services/update_service.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/app_dialogs.dart';

import 'external_url_launcher.dart';

/// 結果類型：呼叫端用來決定是否寫入「忽略此版」。
enum UpdateDialogResult { ignored, later }

enum _UpdateAction { update, cancel, install, retry, openPage, later, ignore }

/// 對話框所處的階段；下載與安裝都留在對話框內進行。
enum _Phase { idle, downloading, ready, failed }

/// 新版提示：在對話框內下載 APK，下載完開系統安裝程式。
///
/// 下載中關閉對話框（返回鍵）會取消下載。使用者在系統安裝畫面按取消，
/// 回到 App 時對話框仍在，可再按「安裝」。
class UpdateDialog extends StatefulWidget {
  const UpdateDialog({super.key, required this.info, required this.installer});

  final UpdateInfo info;
  final AppUpdateInstaller installer;

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  _Phase _phase = _Phase.idle;
  int _received = 0;
  int _total = 0;
  CancelToken? _cancelToken;
  File? _apk;

  @override
  void dispose() {
    _cancelToken?.cancel();
    super.dispose();
  }

  Future<void> _download() async {
    final cancelToken = CancelToken();
    setState(() {
      _phase = _Phase.downloading;
      _received = 0;
      _total = widget.info.assetSize;
      _cancelToken = cancelToken;
    });
    try {
      final apk = await widget.installer.download(
        widget.info,
        cancelToken: cancelToken,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _received = received;
            if (total > 0) _total = total;
          });
        },
      );
      if (!mounted) return;
      setState(() => _apk = apk);
      await _install();
    } catch (e, stack) {
      if (e is DioException && CancelToken.isCancel(e)) {
        if (mounted) setState(() => _phase = _Phase.idle);
        return;
      }
      AppLog.e('Update download failed: $e', error: e, stackTrace: stack);
      if (mounted) setState(() => _phase = _Phase.failed);
    } finally {
      _cancelToken = null;
    }
  }

  Future<void> _install() async {
    final apk = _apk;
    if (apk == null) return;
    setState(() => _phase = _Phase.ready);
    try {
      await widget.installer.install(apk);
    } catch (e, stack) {
      AppLog.e('Opening installer failed: $e', error: e, stackTrace: stack);
      if (mounted) setState(() => _phase = _Phase.failed);
    }
  }

  Future<void> _openReleasePage() async {
    final info = widget.info;
    final url = info.releasePageUrl.isNotEmpty
        ? info.releasePageUrl
        : info.downloadUrl;
    if (url.isEmpty) return;
    await launchExternalUrlWithFeedback(context, url);
  }

  void _onAction(_UpdateAction action) {
    switch (action) {
      case _UpdateAction.update:
        _download();
      case _UpdateAction.cancel:
        _cancelToken?.cancel();
      case _UpdateAction.install:
        _install();
      case _UpdateAction.retry:
        _apk == null ? _download() : _install();
      case _UpdateAction.openPage:
        _openReleasePage();
      case _UpdateAction.later:
        Navigator.of(context).pop(UpdateDialogResult.later);
      case _UpdateAction.ignore:
        Navigator.of(context).pop(UpdateDialogResult.ignored);
    }
  }

  List<AppAlertAction<_UpdateAction>> get _actions => switch (_phase) {
    _Phase.idle => const [
      AppAlertAction(
        label: '立即更新',
        value: _UpdateAction.update,
        isDefault: true,
      ),
      AppAlertAction(label: '稍後提醒', value: _UpdateAction.later),
      AppAlertAction(label: '忽略此版', value: _UpdateAction.ignore),
    ],
    _Phase.downloading => const [
      AppAlertAction(label: '取消下載', value: _UpdateAction.cancel),
    ],
    _Phase.ready => const [
      AppAlertAction(label: '稍後提醒', value: _UpdateAction.later),
      AppAlertAction(
        label: '安裝',
        value: _UpdateAction.install,
        isDefault: true,
      ),
    ],
    _Phase.failed => const [
      AppAlertAction(label: '重試', value: _UpdateAction.retry, isDefault: true),
      AppAlertAction(label: '前往下載頁', value: _UpdateAction.openPage),
      AppAlertAction(label: '稍後提醒', value: _UpdateAction.later),
    ],
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final notes = releaseNotesForDisplay(widget.info.updateLog);
    final status = _status(context);
    return AppAlert<_UpdateAction>(
      title: '發現新版 ${widget.info.versionName}',
      content: notes.isEmpty && status == null
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (notes.isNotEmpty)
                  Text(
                    notes,
                    style: AppTextStyles.bodySm.copyWith(
                      height: 1.5,
                      color: scheme.onSurface,
                    ),
                  ),
                if (notes.isNotEmpty && status != null)
                  const SizedBox(height: AppSpacing.lg),
                ?status,
              ],
            ),
      onAction: _onAction,
      actions: _actions,
    );
  }

  Widget? _status(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = AppTextStyles.bodySm.copyWith(
      color: scheme.onSurface.withValues(alpha: 0.8),
    );
    switch (_phase) {
      case _Phase.idle:
        return null;
      case _Phase.downloading:
        final fraction = _total > 0
            ? (_received / _total).clamp(0.0, 1.0)
            : null;
        final label = fraction == null
            ? '下載中 ${_megabytes(_received)}'
            : '下載中 ${(fraction * 100).floor()}%　'
                  '${_megabytes(_received)} / ${_megabytes(_total)}';
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: AppRadius.pillShape,
              child: LinearProgressIndicator(
                value: fraction,
                backgroundColor: AppChrome.of(context).separator,
                minHeight: 4,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(label, textAlign: TextAlign.center, style: style),
          ],
        );
      case _Phase.ready:
        return Text(
          '下載完成，請在系統畫面確認安裝。',
          textAlign: TextAlign.center,
          style: style,
        );
      case _Phase.failed:
        return Text(
          _apk == null ? '下載失敗，請重試或改到下載頁下載。' : '無法開啟系統安裝程式，請重試或改到下載頁下載。',
          textAlign: TextAlign.center,
          style: style,
        );
    }
  }

  static String _megabytes(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
