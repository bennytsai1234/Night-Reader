import 'dart:async';
import 'dart:io';

import 'package:night_reader/core/exception/user_error.dart';
import 'package:flutter/material.dart';
import 'package:night_reader/core/services/app_file_selection_service.dart';
import 'package:night_reader/core/services/backup_service.dart';
import 'package:night_reader/core/services/restore_service.dart';
import 'package:night_reader/core/sync/sync_service.dart';
import 'package:night_reader/core/sync/sync_settings.dart';
import 'package:night_reader/features/settings/sync_space_page.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/app_dialogs.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:share_plus/share_plus.dart';

class BackupSyncPage extends StatefulWidget {
  const BackupSyncPage({super.key});

  @override
  State<BackupSyncPage> createState() => _BackupSyncPageState();
}

class _BackupSyncPageState extends State<BackupSyncPage> {
  bool _isProcessing = false;

  final SyncService _sync = SyncService.instance;

  @override
  void initState() {
    super.initState();
    _sync.status.addListener(_onSyncStatus);
    unawaited(_sync.load());
  }

  @override
  void dispose() {
    _sync.status.removeListener(_onSyncStatus);
    super.dispose();
  }

  void _onSyncStatus() {
    if (mounted) setState(() {});
  }

  /// 「立即同步」下面那行：同步中、上次失敗的原因，或上次同步的時間。
  static String? _syncSubtitle(SyncStatus status) {
    if (!status.enabled) return null;
    if (status.running) return '同步中…';
    if (status.error case final error?) return '上次同步失敗：$error';
    final at = status.lastSyncAt;
    if (at == null) return '還沒同步過';
    String two(int n) => n.toString().padLeft(2, '0');
    return '上次同步：${at.month}/${at.day} ${two(at.hour)}:${two(at.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    // 備份或還原進行中不離開頁面，結果提示與分享面板才會出現在這裡。
    return PopScope<Object?>(
      canPop: !_isProcessing,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('處理中，完成後才能離開')));
      },
      child: _buildScaffold(),
    );
  }

  Widget _buildScaffold() {
    final status = _sync.status.value;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const GlassNavHeader(title: '備份與同步'),
      body: GroupedListView(
        children: [
          GroupedSection(
            header: '同步',
            footer: '多台手機選同一個同步空間，書架、閱讀進度、書源、替換規則、設定、登入資料與閱讀統計會自動合併；開書時接上另一台讀到的地方。已下載的正文不同步，另一台照書架自己下載。',
            children: [
              GroupedRow(
                leading: const GroupedIconTile(
                  Icons.cloud_sync_outlined,
                  tint: AppTint.azurite,
                ),
                title: '同步空間',
                value: switch (status.space) {
                  SyncSpace.none => '未設定',
                  SyncSpace.webdav => 'WebDAV',
                  SyncSpace.googleDrive => 'Google 雲端硬碟',
                },
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const SyncSpacePage(),
                  ),
                ),
              ),
              GroupedRow(
                leading: const GroupedIconTile(
                  Icons.sync_rounded,
                  tint: AppTint.azurite,
                ),
                title: '立即同步',
                subtitle: _syncSubtitle(status),
                enabled: status.enabled && !status.running,
                showChevron: false,
                onTap: status.enabled && !status.running
                    ? () => unawaited(_sync.syncNow())
                    : null,
              ),
            ],
          ),
          GroupedSection(
            header: '備份',
            footer: '整包存成一個檔，換手機時手動還原；含登入資料。',
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
      if (!mounted) return;
      if (file != null && await file.exists()) {
        await SharePlus.instance.share(
          ShareParams(files: [XFile(file.path)], text: '夜讀備份檔'),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('建立備份失敗')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failureMessage('備份', e))));
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
      final result = await RestoreService().restoreFromZip(file);
      if (!mounted) return;
      final failed = result.failedFiles.join('、');
      final message = result.invalidArchive
          ? '還原失敗，這不是可用的夜讀備份檔'
          : result.failedFiles.isEmpty && result.restoredAny
          ? '還原完成，重新啟動 App 後生效'
          : result.failedFiles.isEmpty
          ? '備份檔裡沒有可還原的資料'
          : result.restoredAny
          ? '部分資料已還原，$failed 匯入失敗；重新啟動 App 後生效'
          : '還原失敗，$failed 無法匯入';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failureMessage('還原', e))));
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }
}
