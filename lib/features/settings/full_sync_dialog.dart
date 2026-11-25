import 'package:flutter/material.dart';
import 'package:night_reader/shared/widgets/text/ui_text.dart';
import 'package:night_reader/core/sync/sync_service.dart';
import 'package:night_reader/features/settings/sync_status_text.dart';
import 'package:night_reader/shared/widgets/popups/app_dialogs.dart';

/// 全面同步（[SyncService.syncAll]）：開一個點外面、按返回都關不掉的進度框，
/// 蓋住整個 App，同步完才關，再用一行提示說完成、失敗或停下（ADR 0046）。
/// 同步途中使用者改的書源或設定，可能在同一輪被雲端的蓋掉或沒送上去，所以
/// 這段時間不讓操作。取消在種類之間停，按了之後照同步的階段寫「正在停下…」；
/// 收掉後那一行照這次要的那一輪怎麼結束（[FullSyncResult]）。「立即全面同步」
/// 與剛選好同步空間都走這裡。
Future<void> runFullSync(BuildContext context, SyncService sync) async {
  final messenger = ScaffoldMessenger.of(context);
  final done = sync.syncAll();
  final dialog = showClosableAppAlert<void>(
    context: context,
    barrierDismissible: false,
    builder: (context, _) => PopScope(
      canPop: false,
      child: ValueListenableBuilder<SyncStatus>(
        valueListenable: sync.status,
        builder: (context, status, _) {
          final stopping = status.phase == SyncPhase.stopping;
          return AppAlert<bool>(
            title: '全面同步中',
            content: FullSyncProgress(status: status),
            actions: [
              AppAlertAction(
                label: stopping ? '正在停下…' : '取消',
                value: true,
                enabled: !stopping,
              ),
            ],
            onAction: (_) => sync.cancelSync(),
          );
        },
      ),
    ),
  );
  final result = await done;
  dialog.close();
  await dialog.closed;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: UiText(switch (result) {
          FullSyncDone() => '全面同步完成',
          FullSyncStopped() => '已停下，同步好的資料留著',
          FullSyncFailed(:final message) => '全面同步失敗：$message',
        }),
      ),
    );
}
