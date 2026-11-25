import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:night_reader/core/backup/bookshelf_exchange_service.dart';
import 'package:night_reader/features/settings/sync_status_text.dart';
import 'package:night_reader/shared/widgets/popups/app_dialogs.dart';

/// 匯入書架檔的內容 [text]，傳回給讀者看的一句結果。書架上的「從檔案或網址
/// 匯入書架」與外部匯入共用。
///
/// Legado 匯出的書架只有書名、作者，要一本一本在書源裡找
/// （[BookshelfExchangeService.importFromText]），會花一段時間：開一個不能
/// 關的進度框，寫找到第幾本，可以取消，取消時找到的留著。其他格式直接匯入。
Future<String> importBookshelfText(
  BuildContext context,
  String text, {
  BookshelfExchangeService? service,
}) async {
  final exchange = service ?? BookshelfExchangeService();
  final total = BookshelfExchangeService.searchCountOf(text);
  if (total == 0) {
    return (await exchange.importFromText(text)).summary ?? '未找到可匯入的書架資料';
  }
  final navigator = Navigator.of(context, rootNavigator: true);
  final cancel = CancelToken();
  final progress = ValueNotifier<int>(0);
  final dialog = showStatefulAppAlert<void>(
    context: context,
    barrierDismissible: false,
    builder: (context, setState, _) => PopScope(
      canPop: false,
      child: AppAlert<bool>(
        title: '匯入書架',
        content: ValueListenableBuilder<int>(
          valueListenable: progress,
          builder: (context, done, _) => SyncProgressView(
            value: done / total,
            label: '在書源裡找第 ${done < total ? done + 1 : total}／$total 本',
          ),
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
  final BookshelfImportResult result;
  try {
    result = await exchange.importFromText(
      text,
      onSearchProgress: (done, _) => progress.value = done,
      cancelToken: cancel,
    );
  } finally {
    navigator.pop();
    await dialog;
    progress.dispose();
  }
  final summary = result.summary;
  if (!cancel.isCancelled) return summary ?? '未找到可匯入的書架資料';
  return summary == null ? '已停下' : '已停下，$summary';
}
