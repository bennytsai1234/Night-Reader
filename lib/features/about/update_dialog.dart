import 'package:flutter/material.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/update_service.dart';
import 'package:url_launcher/url_launcher.dart';

/// 結果類型：呼叫端用來決定是否寫入「忽略此版」。
enum UpdateDialogResult { ignored, later }

class UpdateDialog extends StatelessWidget {
  const UpdateDialog({super.key, required this.info});

  final UpdateInfo info;

  Future<void> _openReleasePage() async {
    final url =
        info.releasePageUrl.isNotEmpty ? info.releasePageUrl : info.downloadUrl;
    if (url.isEmpty) return;
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      AppLog.d('開啟 release 頁失敗: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('發現新版 ${info.versionName}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 360),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [if (info.updateLog.isNotEmpty) Text(info.updateLog)],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed:
              () => Navigator.of(context).pop(UpdateDialogResult.ignored),
          child: const Text('忽略此版'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(UpdateDialogResult.later),
          child: const Text('稍後提醒'),
        ),
        FilledButton(onPressed: _openReleasePage, child: const Text('前往下載')),
      ],
    );
  }
}
