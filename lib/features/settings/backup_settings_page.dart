import 'dart:io';

import 'package:flutter/material.dart';
import 'package:night_reader/core/services/app_file_selection_service.dart';
import 'package:night_reader/core/services/backup_service.dart';
import 'package:night_reader/core/services/restore_service.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/app_dialogs.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:share_plus/share_plus.dart';

class BackupSettingsPage extends StatefulWidget {
  const BackupSettingsPage({super.key});

  @override
  State<BackupSettingsPage> createState() => _BackupSettingsPageState();
}

class _BackupSettingsPageState extends State<BackupSettingsPage> {
  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const GlassNavHeader(title: '備份與還原'),
      body: GroupedListView(
        children: [
          GroupedSection(
            header: '本地備份與還原',
            footer:
                '建立備份會產生 ZIP 檔，再選擇儲存或分享位置；還原時選擇 ZIP 備份檔並匯入書架、書源與設定。',
            children: [
              GroupedRow(
                leading: const GroupedIconTile(
                  Icons.backup_outlined,
                  tint: AppTint.tea,
                ),
                title: '建立備份',
                enabled: !_isProcessing,
                onTap: _isProcessing ? null : _handleManualBackup,
              ),
              GroupedRow(
                leading: const GroupedIconTile(
                  Icons.restore_rounded,
                  tint: AppTint.tea,
                ),
                title: '從備份檔還原',
                enabled: !_isProcessing,
                onTap: _isProcessing ? null : _handleManualRestore,
              ),
            ],
          ),
          if (_isProcessing)
            const Padding(
              padding: EdgeInsets.only(top: AppSpacing.xl),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Future<void> _handleManualBackup() async {
    setState(() => _isProcessing = true);
    try {
      final file = await BackupService().createBackupZip();
      if (file != null && await file.exists()) {
        await SharePlus.instance.share(
          ShareParams(files: [XFile(file.path)], text: '夜讀備份檔'),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('建立備份失敗')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('備份出錯: $e')));
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _handleManualRestore() async {
    final path = await AppFileSelectionService.instance.pickBackupArchivePath();
    if (!mounted) return;

    if (path == null) return;

    final confirmed = await showAppConfirm(
      context: context,
      title: '還原這份備份？',
      message: '備份中的書架、書源與設定會匯入目前資料；相同項目會以備份內容更新。',
      confirmLabel: '開始還原',
    );
    if (!confirmed || !mounted) return;

    final file = File(path);
    setState(() => _isProcessing = true);
    try {
      final success = await RestoreService().restoreFromZip(file);
      if (!mounted) return;
      if (success) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('還原完成，重新啟動 App 後生效')));
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('還原失敗，備份檔格式不正確')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('還原出錯: $e')));
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }
}
