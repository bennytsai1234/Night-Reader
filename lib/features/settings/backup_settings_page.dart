import 'package:flutter/material.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:night_reader/core/services/backup_service.dart';
import 'package:night_reader/core/services/restore_service.dart';
import 'dart:io';

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
      appBar: AppBar(title: const Text('備份與還原')),
      body: ListTileTheme(
        data: const ListTileThemeData(
          contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        ),
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
          children: [
            _buildSectionTitle('本地備份與還原'),
            ListTile(
              title: const Text('建立備份'),
              subtitle: Text(
                '建立 ZIP 備份後，選擇儲存或分享位置',
                style: AppTextStyles.bodySm.copyWith(height: 1.4),
              ),
              leading: const Icon(Icons.backup_outlined),
              onTap: _isProcessing ? null : _handleManualBackup,
            ),
            ListTile(
              title: const Text('從備份檔還原'),
              subtitle: Text(
                '選擇 ZIP 備份檔並匯入書架、書源與設定',
                style: AppTextStyles.bodySm.copyWith(height: 1.4),
              ),
              leading: const Icon(Icons.restore),
              onTap: _isProcessing ? null : _handleManualRestore,
            ),
            if (_isProcessing)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.sm,
      ),
      child: Text(
        title,
        style: AppTextStyles.bodySm.copyWith(
          height: 1.3,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.primary,
        ),
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
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (!mounted) return;

    final path = result?.files.single.path;
    if (path == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            shape: const RoundedRectangleBorder(
              borderRadius: AppRadius.cardXl,
            ),
            title: const Text('還原這份備份？'),
            content: Text(
              '備份中的書架、書源與設定會匯入目前資料；相同項目會以備份內容更新。',
              style: AppTextStyles.bodyBase.copyWith(height: 1.5),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('開始還原'),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;

    final file = File(path);
    setState(() => _isProcessing = true);
    try {
      final success = await RestoreService().restoreFromZip(file);
      if (!mounted) return;
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('還原完成，重新啟動 App 後生效')),
        );
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
