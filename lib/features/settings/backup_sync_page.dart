import 'dart:async';
import 'dart:io';

import 'package:night_reader/core/exception/user_error.dart';
import 'package:flutter/material.dart';
import 'package:night_reader/core/services/app_file_selection_service.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/backup_service.dart';
import 'package:night_reader/core/services/restore_service.dart';
import 'package:night_reader/core/sync/sync_service.dart';
import 'package:night_reader/core/sync/sync_settings.dart';
import 'package:night_reader/features/settings/sync_space_page.dart';
import 'package:night_reader/features/settings/sync_status_text.dart';
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
  bool _loaded = false;

  final SyncService _sync = SyncService.instance;

  @override
  void initState() {
    super.initState();
    _sync.status.addListener(_onSyncStatus);
    unawaited(_loadSyncStatus());
  }

  Future<void> _loadSyncStatus() async {
    try {
      await _sync.load();
    } catch (error, stackTrace) {
      AppLog.e('讀取同步狀態失敗', error: error, stackTrace: stackTrace);
    } finally {
      if (mounted) setState(() => _loaded = true);
    }
  }

  @override
  void dispose() {
    _sync.status.removeListener(_onSyncStatus);
    super.dispose();
  }

  void _onSyncStatus() {
    if (mounted) setState(() {});
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
        // 同步空間與上次同步時間讀好才算骨架，避免新增副標撐高整列。
        ready: _loaded,
        children: [
          GroupedSection(
            header: '同步',
            footer: '多台手機選同一個同步空間，閱讀進度自動同步，開書時接上另一台讀到的地方。書架、書籤、標註、書源、替換規則、設定、登入資料與閱讀統計按「立即全面同步」才合併，同步時暫時不能操作。已下載的正文不同步，另一台照書架自己下載。',
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
                title: '立即全面同步',
                subtitle: syncStatusSubtitle(status),
                // 正在同步閱讀進度時也能按：等那一輪做完接著全面同步。
                enabled: status.enabled,
                showChevron: false,
                onTap: status.enabled ? () => unawaited(_syncAll()) : null,
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

  /// 全面同步：開一個點外面、按返回都關不掉的進度框，蓋住整個 App，同步完
  /// 才關（ADR 0046）。同步途中使用者改的書源或設定，可能在同一輪被雲端的
  /// 蓋掉或沒送上去，所以這段時間不讓操作。取消在種類之間停。
  Future<void> _syncAll() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context, rootNavigator: true);
    var cancelled = false;
    final done = _sync.syncAll();
    final dialog = showStatefulAppAlert<void>(
      context: context,
      barrierDismissible: false,
      builder: (context, setState, _) => PopScope(
        canPop: false,
        child: AppAlert<bool>(
          title: '全面同步中',
          content: ValueListenableBuilder<SyncStatus>(
            valueListenable: _sync.status,
            builder: (context, status, _) => FullSyncProgress(status: status),
          ),
          actions: [
            AppAlertAction(
              label: cancelled ? '正在停下…' : '取消',
              value: true,
              enabled: !cancelled,
            ),
          ],
          onAction: (_) {
            setState(() => cancelled = true);
            _sync.cancelSync();
          },
        ),
      ),
    );
    await done;
    navigator.pop();
    await dialog;
    final error = _sync.status.value.error;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            error != null
                ? '全面同步失敗：$error'
                : cancelled
                ? '已停下，同步好的資料留著'
                : '全面同步完成',
          ),
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
