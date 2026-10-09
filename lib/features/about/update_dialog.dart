import 'package:flutter/material.dart';
import 'package:night_reader/core/services/update_service.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/widgets/app_dialogs.dart';

import 'external_url_launcher.dart';

/// 結果類型：呼叫端用來決定是否寫入「忽略此版」。
enum UpdateDialogResult { ignored, later }

/// 對話框按鈕；「前往下載」只開啟連結，不關閉對話框。
enum _UpdateAction { download, later, ignore }

class UpdateDialog extends StatelessWidget {
  const UpdateDialog({super.key, required this.info});

  final UpdateInfo info;

  Future<void> _openReleasePage(BuildContext context) async {
    final url = info.releasePageUrl.isNotEmpty
        ? info.releasePageUrl
        : info.downloadUrl;
    if (url.isEmpty) return;
    await launchExternalUrlWithFeedback(context, url);
  }

  @override
  Widget build(BuildContext context) {
    return AppAlert<_UpdateAction>(
      title: '發現新版 ${info.versionName}',
      content: info.updateLog.isEmpty
          ? null
          : Text(
              info.updateLog,
              style: AppTextStyles.bodySm.copyWith(
                height: 1.5,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
      onAction: (action) {
        switch (action) {
          case _UpdateAction.download:
            _openReleasePage(context);
          case _UpdateAction.later:
            Navigator.of(context).pop(UpdateDialogResult.later);
          case _UpdateAction.ignore:
            Navigator.of(context).pop(UpdateDialogResult.ignored);
        }
      },
      actions: const [
        AppAlertAction(
          label: '前往下載',
          value: _UpdateAction.download,
          isDefault: true,
        ),
        AppAlertAction(label: '稍後提醒', value: _UpdateAction.later),
        AppAlertAction(label: '忽略此版', value: _UpdateAction.ignore),
      ],
    );
  }
}
