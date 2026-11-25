import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:night_reader/core/backup/bookshelf_exchange_service.dart';
import 'package:night_reader/features/settings/sync_status_text.dart';
import 'package:night_reader/shared/widgets/popups/app_dialogs.dart';

/// 匯入解析好的書架檔 [file]（[BookshelfExchangeService.parse]），傳回給
/// 讀者看的一句結果。書架上的「從檔案或網址匯入書架」與外部匯入共用；不是
/// 書架檔（[file] 是 null）時什麼都不匯入，回「未找到可匯入的書架資料」。
///
/// Legado 匯出的書架只有書名、作者，要一本一本在書源裡找
/// （[BookshelfExchangeService.importFile]），會花一段時間：開始找時開
/// 一個不能關的進度框，寫找到第幾本（分母是實際要找的本數，書架上已有的
/// 不算），可以取消，取消時找到的留著。不用找的直接匯入，不開進度框。
Future<String> importBookshelfFile(
  BuildContext context,
  BookshelfFile? file, {
  BookshelfExchangeService? service,
}) async {
  final exchange = service ?? BookshelfExchangeService();
  final navigator = Navigator.of(context, rootNavigator: true);
  final cancel = CancelToken();
  final progress = ValueNotifier<(int, int)>((0, 0));
  Future<void>? dialog;
  void showProgress() {
    dialog = showStatefulAppAlert<void>(
      context: context,
      barrierDismissible: false,
      builder: (context, setState, _) => PopScope(
        canPop: false,
        child: AppAlert<bool>(
          title: '匯入書架',
          content: ValueListenableBuilder<(int, int)>(
            valueListenable: progress,
            builder: (context, value, _) {
              final (done, total) = value;
              return SyncProgressView(
                value: total == 0 ? 0 : done / total,
                label: '在書源裡找第 ${done < total ? done + 1 : total}／$total 本',
              );
            },
          ),
          actions: [
            AppAlertAction(
              label: cancel.isCancelled ? '正在停下…' : '取消',
              value: true,
              enabled: !cancel.isCancelled,
            ),
          ],
          onAction: (_) => setState(cancel.cancel),
        ),
      ),
    );
  }

  final BookshelfImportResult result;
  try {
    result = await exchange.importFile(
      file,
      onSearchProgress: (done, total) {
        progress.value = (done, total);
        if (dialog == null && context.mounted) showProgress();
      },
      cancelToken: cancel,
    );
  } finally {
    // 只關自己開的進度框：沒開時 pop 會把頁面關掉。
    if (dialog case final shown?) {
      navigator.pop();
      await shown;
    }
    progress.dispose();
  }
  final summary = result.summary;
  if (!cancel.isCancelled) return summary ?? '未找到可匯入的書架資料';
  return summary == null ? '已停下' : '已停下，$summary';
}
