import 'package:flutter/material.dart';
import 'package:night_reader/core/sync/sync_service.dart';
import 'package:night_reader/features/settings/sync_status_text.dart';
import 'package:night_reader/shared/widgets/app_dialogs.dart';

/// 全面同步（[SyncService.syncAll]）：開一個點外面、按返回都關不掉的進度框，
/// 蓋住整個 App，同步完才關，再用一行提示說完成、失敗或停下（ADR 0046）。
/// 同步途中使用者改的書源或設定，可能在同一輪被雲端的蓋掉或沒送上去，所以
/// 這段時間不讓操作。取消在種類之間停。「立即全面同步」與剛選好同步空間
/// 都走這裡。
Future<void> runFullSync(BuildContext context, SyncService sync) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  var cancelled = false;
  final done = sync.syncAll();
  final dialog = showStatefulAppAlert<void>(
    context: context,
    barrierDismissible: false,
    builder: (context, setState, _) => PopScope(
      canPop: false,
      child: AppAlert<bool>(
        title: '全面同步中',
        content: ValueListenableBuilder<SyncStatus>(
          valueListenable: sync.status,
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
          sync.cancelSync();
        },
      ),
    ),
  );
  await done;
  navigator.pop();
  await dialog;
  final error = sync.status.value.error;
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
