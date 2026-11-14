import 'package:flutter/material.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/sync/local_book_sync.dart';
import 'package:night_reader/core/sync/sync_service.dart';
import 'package:night_reader/core/sync/sync_store.dart';
import 'package:night_reader/features/settings/sync_status_text.dart';
import 'package:night_reader/shared/widgets/app_dialogs.dart';

/// 「同步本地書」（ADR 0039）：先比對出要做的事（比對時開一個進度框），
/// 顯示要上傳、下載幾本、各多少 MB、要移出與刪掉幾本，使用者確定才開始。
/// 開始後同全面同步（`runFullSync`）開一個點外面、按返回都關不掉的進度框，
/// 一次一本，可以取消，取消在兩本之間停，傳好的留著。做完用一行提示說結果；
/// 有沒做成的，列出哪本、為什麼，下次按的時候重做。
Future<void> runLocalBookSync(BuildContext context, SyncService sync) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  void tell(String text) => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  // 比對要補算舊書的指紋、讀雲端的小紀錄，通常一下子；取消就不等它。
  final prepared = _prepare(sync);
  var gaveUp = false;
  final comparing = showStatefulAppAlert<void>(
    context: context,
    barrierDismissible: false,
    builder: (context, _, _) => PopScope(
      canPop: false,
      child: AppAlert<bool>(
        title: '同步本地書',
        content: const SyncProgressView(value: null, label: '比對中…'),
        actions: const [AppAlertAction(label: '取消', value: true)],
        onAction: (_) {
          gaveUp = true;
          navigator.pop();
        },
      ),
    ),
  );
  final (:session, :plan, :error) = await prepared;
  if (!gaveUp) navigator.pop();
  await comparing;
  if (gaveUp || !context.mounted) return;
  if (error != null) return tell('同步本地書失敗：$error');
  if (session == null || plan == null) return;
  if (plan.isEmpty) return tell('本地書都同步好了');

  final confirmed = await showAppConfirm(
    context: context,
    title: '同步本地書？',
    message: localBookSyncSummary(plan),
    confirmLabel: '開始同步',
  );
  if (!confirmed || !context.mounted) return;

  var cancelled = false;
  final progress = ValueNotifier<LocalBookSyncProgress?>(null);
  final done = session.run(
    plan,
    onProgress: (value) => progress.value = value,
    cancelled: () => cancelled,
  );
  final dialog = showStatefulAppAlert<void>(
    context: context,
    barrierDismissible: false,
    builder: (context, setState, _) => PopScope(
      canPop: false,
      child: AppAlert<bool>(
        title: '同步本地書中',
        content: ValueListenableBuilder<LocalBookSyncProgress?>(
          valueListenable: progress,
          builder: (context, value, _) => SyncProgressView(
            value: value == null ? null : (value.step - 1) / value.total,
            label: value == null ? '準備中…' : localBookProgressLabel(value),
          ),
        ),
        actions: [
          AppAlertAction(
            label: cancelled ? '正在停下…' : '取消',
            value: true,
            enabled: !cancelled,
          ),
        ],
        onAction: (_) => setState(() => cancelled = true),
      ),
    ),
  );
  final LocalBookSyncResult result;
  try {
    result = await done;
  } finally {
    navigator.pop();
    await dialog;
    progress.dispose();
  }
  // 下載的書接上另一台讀到的地方。
  if (plan.of(LocalBookAction.download).isNotEmpty) sync.syncProgress();
  if (!context.mounted) return;
  if (result.failures.isEmpty) {
    return tell(result.cancelled ? '已停下，傳好的書留著' : '本地書同步完成');
  }
  await showAppAlert<void>(
    context: context,
    title: '有 ${result.failures.length} 本沒同步成功',
    message: [
      for (final (:task, :reason) in result.failures) '《${task.name}》：$reason',
      '',
      '下次按「同步本地書」會再試。',
    ].join('\n'),
    actions: const [AppAlertAction(label: '知道了', value: null)],
  );
}

Future<({LocalBookSync? session, LocalBookSyncPlan? plan, String? error})>
_prepare(SyncService sync) async {
  try {
    final session = await sync.localBooks();
    if (session == null) return (session: null, plan: null, error: null);
    return (session: session, plan: await session.plan(), error: null);
  } catch (error, stackTrace) {
    AppLog.e('比對本地書失敗', error: error, stackTrace: stackTrace);
    return (
      session: null,
      plan: null,
      error: switch (error) {
        SyncStoreException(:final message) => message,
        FormatException() => '同步空間裡的紀錄不是夜讀寫的，沒有動它',
        _ => '比對失敗',
      },
    );
  }
}

/// 確認框的說明：要上傳、下載幾本與各多少 MB，要移出與刪掉幾本。
String localBookSyncSummary(LocalBookSyncPlan plan) {
  final uploads = plan.of(LocalBookAction.upload).length;
  final downloads = plan.of(LocalBookAction.download).length;
  final removals = plan.of(LocalBookAction.removeHere).length;
  final deletions = plan.of(LocalBookAction.deleteRemote).length;
  return [
    if (uploads > 0)
      '上傳 $uploads 本，共 ${formatMegabytes(plan.bytesOf(LocalBookAction.upload))}',
    if (downloads > 0)
      '下載 $downloads 本，共 ${formatMegabytes(plan.bytesOf(LocalBookAction.download))}',
    if (removals > 0) '從這台書架移出 $removals 本（另一台移出了）',
    if (deletions > 0) '刪掉雲端的 $deletions 本（這台移出了）',
    if (uploads + downloads > 0) ...['', '沒連 Wi-Fi 時用行動數據傳。'],
  ].join('\n');
}

/// 進度框的說明：做第幾本、做什麼、書名與大小。
String localBookProgressLabel(LocalBookSyncProgress progress) {
  final (:step, :total, :task) = progress;
  final size = formatMegabytes(task.size);
  final what = switch (task.action) {
    LocalBookAction.upload => '上傳《${task.name}》（$size）',
    LocalBookAction.download => '下載《${task.name}》（$size）',
    LocalBookAction.removeHere => '移出《${task.name}》',
    LocalBookAction.deleteRemote => '刪掉雲端的《${task.name}》',
  };
  return '第 $step／$total 本：$what';
}

/// 位元組換成「12.3 MB」；有內容但不到 0.1 MB 的寫成 0.1 MB。
String formatMegabytes(int bytes) {
  final megabytes = bytes / (1024 * 1024);
  final shown = bytes > 0 && megabytes < 0.1 ? 0.1 : megabytes;
  return '${shown.toStringAsFixed(1)} MB';
}
