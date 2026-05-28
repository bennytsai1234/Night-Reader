import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:night_reader/core/services/download_service.dart';
import 'package:night_reader/core/models/download_task.dart';
import 'package:night_reader/shared/theme/context_ext.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';

/// DownloadManagerPage - 全域背景下載管理頁面
class DownloadManagerPage extends StatelessWidget {
  const DownloadManagerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final service = context.watch<DownloadService>();
    final tasks = service.tasks;

    return Scaffold(
      appBar: AppBar(
        title: const Text('背景下載佇列'),
        actions: [
          IconButton(
            icon: Icon(
              service.isPaused
                  ? Icons.play_circle_outline
                  : Icons.pause_circle_outline,
            ),
            tooltip: service.isPaused ? '恢復全部' : '暫停全部',
            onPressed: service.togglePause,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: '清除已完成',
            onPressed: () {
              // 深度還原：清除已完成的任務
              for (var task in tasks.where((t) => t.isCompleted).toList()) {
                service.removeTask(task.bookUrl);
              }
            },
          ),
        ],
      ),
      body:
          tasks.isEmpty
              ? _buildEmptyState(context)
              : Column(
                children: [
                  _buildQueueSummary(context, service, tasks),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
                      itemCount: tasks.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final task = tasks[index];
                        return _buildTaskTile(
                          context,
                          service,
                          task,
                          index,
                          tasks.length,
                        );
                      },
                    ),
                  ),
                ],
              ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.download_done_rounded,
            size: 64,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.1),
          ),
          const SizedBox(height: 16),
          Text(
            '暫無背景下載任務',
            style: TextStyle(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQueueSummary(
    BuildContext context,
    DownloadService service,
    List<DownloadTask> tasks,
  ) {
    final waiting = tasks.where((task) => task.isWaiting).length;
    final running = tasks.where((task) => task.isDownloading).length;
    final paused = tasks.where((task) => task.isPaused).length;
    final failed = tasks.where((task) => task.hasFailures).length;
    final latestUpdate = tasks.fold<int>(
      0,
      (latest, task) =>
          task.lastUpdateTime > latest ? task.lastUpdateTime : latest,
    );

    return Material(
      color: Theme.of(
        context,
      ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _summaryChip(context, '等待', '$waiting'),
                _summaryChip(context, '下載中', '$running'),
                _summaryChip(context, '暫停', '$paused'),
                _summaryChip(context, '失敗', '$failed'),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              service.isBookshelfRefreshing
                  ? '書架正在檢查更新，下載會等檢查完成後繼續'
                  : '最近任務更新：${_formatTimestamp(latestUpdate)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryChip(BuildContext context, String label, String value) {
    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text('$label $value'),
      side: BorderSide(color: Theme.of(context).dividerColor),
    );
  }

  Widget _buildTaskTile(
    BuildContext context,
    DownloadService service,
    DownloadTask task,
    int index,
    int taskCount,
  ) {
    final rawProgress =
        task.totalCount <= 0 ? 0.0 : task.successCount / task.totalCount;
    final progress =
        rawProgress < 0
            ? 0.0
            : rawProgress > 1
            ? 1.0
            : rawProgress;
    final canRetry = task.isFailed || task.errorCount > 0;
    final failureSummary = task.failureSummary;

    return ListTile(
      title: Text(
        task.bookName,
        style: AppTextStyles.bodySm.copyWith(fontWeight: FontWeight.bold),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: progress,
            backgroundColor:
                Theme.of(context).colorScheme.surfaceContainerHighest,
            minHeight: 4,
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _statusText(task),
                style: AppTextStyles.labelXs.copyWith(
                  color: _statusColor(context, task),
                ),
              ),
              if (task.isDownloading)
                Text(
                  '正在下載...',
                  style: AppTextStyles.labelXs.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
            ],
          ),
          if (failureSummary != null) ...[
            const SizedBox(height: 4),
            Text(
              failureSummary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.labelXs.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canRetry)
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              tooltip: '重試',
              onPressed: () => service.retryTask(task.bookUrl),
            )
          else if (!task.isCompleted)
            IconButton(
              icon: Icon(
                task.isPaused ? Icons.play_arrow : Icons.pause,
                size: 20,
              ),
              tooltip: task.isPaused ? '繼續' : '暫停',
              onPressed:
                  () =>
                      task.isPaused
                          ? service.resumeTask(task.bookUrl)
                          : service.pauseTask(task.bookUrl),
            ),
          PopupMenuButton<String>(
            tooltip: '更多操作',
            onSelected:
                (value) =>
                    _handleTaskMenu(context, service, task, index, value),
            itemBuilder:
                (context) => [
                  PopupMenuItem(
                    value: 'up',
                    enabled: index > 0,
                    child: const ListTile(
                      leading: Icon(Icons.arrow_upward),
                      title: Text('上移'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'down',
                    enabled: index < taskCount - 1,
                    child: const ListTile(
                      leading: Icon(Icons.arrow_downward),
                      title: Text('下移'),
                    ),
                  ),
                  if (failureSummary != null)
                    const PopupMenuItem(
                      value: 'details',
                      child: ListTile(
                        leading: Icon(Icons.info_outline),
                        title: Text('查看失敗原因'),
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      leading: Icon(Icons.close),
                      title: Text('刪除任務'),
                    ),
                  ),
                ],
          ),
        ],
      ),
    );
  }

  void _handleTaskMenu(
    BuildContext context,
    DownloadService service,
    DownloadTask task,
    int index,
    String value,
  ) {
    switch (value) {
      case 'up':
        service.moveTask(task.bookUrl, -1);
        break;
      case 'down':
        service.moveTask(task.bookUrl, 1);
        break;
      case 'details':
        _showFailureDetails(context, task);
        break;
      case 'delete':
        service.removeTask(task.bookUrl);
        break;
    }
  }

  void _showFailureDetails(BuildContext context, DownloadTask task) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('下載失敗原因'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _detailRow('書籍', task.bookName),
                _detailRow('分類', task.lastErrorReason ?? '下載失敗'),
                if (task.lastErrorChapterIndex != null)
                  _detailRow('章節', '第 ${task.lastErrorChapterIndex! + 1} 章'),
                _detailRow('失敗章節數', '${task.errorCount}'),
                _detailRow('原因', task.lastErrorMessage ?? '未記錄詳細原因'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('關閉'),
              ),
            ],
          ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 76, child: Text(label)),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  String _statusText(DownloadTask task) {
    if (task.isCompleted && task.errorCount == 0) {
      return '下載完成';
    }
    if (task.isFailed || task.errorCount > 0) {
      return '下載失敗 ${task.successCount}/${task.totalCount} 章，失敗 ${task.errorCount} 章';
    }
    if (task.isPaused) {
      return '已暫停 ${task.successCount}/${task.totalCount} 章';
    }
    if (task.isWaiting) {
      return '等待中 ${task.successCount}/${task.totalCount} 章';
    }
    return '${task.successCount} / ${task.totalCount} 章';
  }

  Color _statusColor(BuildContext context, DownloadTask task) {
    if (task.isFailed || task.errorCount > 0)
      return Theme.of(context).colorScheme.error;
    if (task.isPaused) return context.warning;
    if (task.isCompleted) return context.success;
    return Theme.of(context).colorScheme.onSurfaceVariant;
  }

  String _formatTimestamp(int timestamp) {
    if (timestamp <= 0) return '尚未更新';
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    String two(int value) => value.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}';
  }
}
