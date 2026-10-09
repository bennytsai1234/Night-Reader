import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:night_reader/core/services/download_service.dart';
import 'package:night_reader/core/models/download_task.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/context_ext.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/widgets/app_dialogs.dart';
import 'package:night_reader/shared/widgets/app_state_view.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/glass_menu.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:night_reader/shared/widgets/swipe_actions.dart';

/// DownloadManagerPage - 全域背景下載管理頁面
class DownloadManagerPage extends StatelessWidget {
  const DownloadManagerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final service = context.watch<DownloadService>();
    final tasks = service.tasks;
    final hasActiveTasks = tasks.any((task) => !task.isCompleted);
    final hasCompletedTasks = tasks.any((task) => task.isCompleted);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassNavHeader(
        title: '背景下載佇列',
        actions: [
          GlassIconButton(
            icon: service.isPaused
                ? Icons.play_arrow_rounded
                : Icons.pause_rounded,
            tooltip: service.isPaused ? '恢復全部' : '暫停全部',
            onPressed: hasActiveTasks ? service.togglePause : null,
          ),
          GlassIconButton(
            icon: Icons.delete_sweep_outlined,
            tooltip: '清除已完成',
            onPressed: hasCompletedTasks
                ? () {
                    for (final task
                        in tasks.where((task) => task.isCompleted).toList()) {
                      service.removeTask(task.bookUrl);
                    }
                  }
                : null,
          ),
        ],
      ),
      body: tasks.isEmpty
          ? Padding(
              padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
              child: const AppStateView(
                icon: Icons.download_done_rounded,
                title: '暫無背景下載任務',
                description: '從書籍詳情加入下載後，進度會顯示在這裡。',
              ),
            )
          : SwipeActionsGroup(
              child: GroupedListView(
                children: [
                  _buildQueueSummary(context, service, tasks),
                  GroupedSection(
                    header: '任務',
                    children: [
                      for (var index = 0; index < tasks.length; index++)
                        _buildTaskTile(
                          context,
                          service,
                          tasks[index],
                          index,
                          tasks.length,
                        ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildQueueSummary(
    BuildContext context,
    DownloadService service,
    List<DownloadTask> tasks,
  ) {
    // 「暫停全部」時進行中與等待中的任務都算暫停。
    final globallyPaused = service.isPaused;
    final waiting = globallyPaused
        ? 0
        : tasks.where((task) => task.isWaiting).length;
    final running = globallyPaused
        ? 0
        : tasks.where((task) => task.isDownloading).length;
    final paused = tasks
        .where(
          (task) =>
              task.isPaused ||
              (globallyPaused && (task.isWaiting || task.isDownloading)),
        )
        .length;
    final failed = tasks.where((task) => task.hasFailures).length;
    final latestUpdate = tasks.fold<int>(
      0,
      (latest, task) =>
          task.lastUpdateTime > latest ? task.lastUpdateTime : latest,
    );

    return GroupedSection(
      topGap: AppSpacing.sm,
      footer: service.isBookshelfRefreshing
          ? '書架正在檢查更新，下載會等檢查完成後繼續'
          : '最近任務更新：${_formatTimestamp(latestUpdate)}',
      children: [
        GroupedContent(
          child: Row(
            children: [
              _summaryStat(context, '等待', waiting),
              _summaryStat(context, '下載中', running),
              _summaryStat(context, '暫停', paused),
              _summaryStat(context, '失敗', failed),
            ],
          ),
        ),
      ],
    );
  }

  Widget _summaryStat(BuildContext context, String label, int value) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Semantics(
        label: '$label $value',
        excludeSemantics: true,
        child: Column(
          children: [
            Text(
              '$value',
              style: AppTextStyles.titleMd.copyWith(color: scheme.onSurface),
            ),
            Text(
              label,
              style: AppTextStyles.uiXs.copyWith(
                color: AppChrome.of(context).sectionText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskTile(
    BuildContext context,
    DownloadService service,
    DownloadTask task,
    int index,
    int taskCount,
  ) {
    final chrome = AppChrome.of(context);
    final scheme = Theme.of(context).colorScheme;
    final rawProgress = task.totalCount <= 0
        ? 0.0
        : task.successCount / task.totalCount;
    final progress = rawProgress < 0
        ? 0.0
        : rawProgress > 1
        ? 1.0
        : rawProgress;
    final active = task.isDownloading || task.isWaiting;
    // 下載中有章節失敗時照樣可以暫停；停下來之後才換成重試。
    final canRetry = task.isFailed || (task.errorCount > 0 && !active);
    // 「暫停全部」時進行中的任務其實停著，單本的暫停／繼續交給頁首的恢復全部。
    final globallyPaused = service.isPaused && active;
    final failureSummary = task.failureSummary;

    Widget? control;
    if (globallyPaused) {
      control = null;
    } else if (canRetry) {
      control = _TaskControlButton(
        icon: Icons.refresh_rounded,
        tooltip: '重試',
        onPressed: () => service.retryTask(task.bookUrl),
      );
    } else if (!task.isCompleted) {
      control = _TaskControlButton(
        icon: task.isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
        tooltip: task.isPaused ? '繼續' : '暫停',
        onPressed: () => task.isPaused
            ? service.resumeTask(task.bookUrl)
            : service.pauseTask(task.bookUrl),
      );
    }

    final row = Builder(
      builder: (rowContext) => InkWell(
        onTap: () => _showTaskMenu(rowContext, service, task, index, taskCount),
        onLongPress: () =>
            _showTaskMenu(rowContext, service, task, index, taskCount),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppGrouped.rowPadding,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      task.bookName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyBase.copyWith(
                        height: 1.3,
                        fontWeight: FontWeight.w500,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    ClipRRect(
                      borderRadius: AppRadius.pillShape,
                      child: LinearProgressIndicator(
                        value: progress,
                        backgroundColor: chrome.separator,
                        minHeight: 4,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            _statusText(task, globallyPaused: globallyPaused),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.bodySm.copyWith(
                              height: 1.3,
                              color: _statusColor(
                                context,
                                task,
                                globallyPaused: globallyPaused,
                              ),
                            ),
                          ),
                        ),
                        if (task.isDownloading && !globallyPaused) ...[
                          const SizedBox(width: AppSpacing.md),
                          Text(
                            '正在下載…',
                            style: AppTextStyles.bodySm.copyWith(
                              height: 1.3,
                              color: scheme.primary,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (failureSummary != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        failureSummary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySm.copyWith(
                          height: 1.3,
                          color: context.danger,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (control != null) ...[
                const SizedBox(width: AppSpacing.md),
                control,
              ],
            ],
          ),
        ),
      ),
    );

    return SwipeActions(
      key: ValueKey(task.bookUrl),
      trailing: [
        SwipeAction(
          label: '刪除',
          icon: Icons.delete_outline_rounded,
          color: context.danger,
          destructive: true,
          onPressed: () => service.removeTask(task.bookUrl),
        ),
      ],
      child: Material(color: chrome.groupedSurface, child: row),
    );
  }

  Future<void> _showTaskMenu(
    BuildContext rowContext,
    DownloadService service,
    DownloadTask task,
    int index,
    int taskCount,
  ) async {
    final value = await showGlassMenu<String>(
      context: rowContext,
      anchor: globalRectOf(rowContext),
      entries: [
        GlassMenuItem(
          value: 'up',
          label: '上移',
          icon: Icons.arrow_upward_rounded,
          enabled: index > 0,
        ),
        GlassMenuItem(
          value: 'down',
          label: '下移',
          icon: Icons.arrow_downward_rounded,
          enabled: index < taskCount - 1,
        ),
        if (task.failureSummary != null)
          const GlassMenuItem(
            value: 'details',
            label: '查看失敗原因',
            icon: Icons.info_outline_rounded,
          ),
        const GlassMenuDivider(),
        const GlassMenuItem(
          value: 'delete',
          label: '刪除任務',
          icon: Icons.delete_outline_rounded,
          destructive: true,
        ),
      ],
    );
    if (value == null || !rowContext.mounted) return;
    _handleTaskMenu(rowContext, service, task, index, value);
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
    final chrome = AppChrome.of(context);
    final scheme = Theme.of(context).colorScheme;
    Widget detailRow(String label, String value) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 76,
              child: Text(
                label,
                style: AppTextStyles.bodySm.copyWith(color: chrome.sectionText),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: AppTextStyles.bodySm.copyWith(color: scheme.onSurface),
              ),
            ),
          ],
        ),
      );
    }

    showAppAlert<void>(
      context: context,
      title: '下載失敗原因',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          detailRow('書籍', task.bookName),
          detailRow('失敗類型', task.lastErrorReason ?? '下載失敗'),
          if (task.lastErrorChapterIndex != null)
            detailRow('章節', '第 ${task.lastErrorChapterIndex! + 1} 章'),
          detailRow('失敗章節數', '${task.errorCount}'),
          detailRow('原因', task.lastErrorMessage ?? '未記錄詳細原因'),
        ],
      ),
      actions: const [
        AppAlertAction(label: '關閉', value: null, isDefault: true),
      ],
    );
  }

  String _statusText(DownloadTask task, {required bool globallyPaused}) {
    if (task.isCompleted && task.errorCount == 0) {
      return '下載完成';
    }
    final active = task.isDownloading || task.isWaiting;
    if (task.isFailed || (task.errorCount > 0 && !active)) {
      return '下載失敗 ${task.successCount}/${task.totalCount} 章，失敗 ${task.errorCount} 章';
    }
    if (globallyPaused) {
      return '已暫停全部 ${task.successCount}/${task.totalCount} 章';
    }
    if (task.isPaused) {
      return '已暫停 ${task.successCount}/${task.totalCount} 章';
    }
    if (task.isWaiting) {
      return '等待中 ${task.successCount}/${task.totalCount} 章';
    }
    return '${task.successCount} / ${task.totalCount} 章';
  }

  Color _statusColor(
    BuildContext context,
    DownloadTask task, {
    required bool globallyPaused,
  }) {
    final active = task.isDownloading || task.isWaiting;
    if (task.isFailed || (task.errorCount > 0 && !active)) {
      return context.danger;
    }
    if (task.isPaused || globallyPaused) return context.warning;
    if (task.isCompleted) return context.success;
    return AppChrome.of(context).sectionText;
  }

  String _formatTimestamp(int timestamp) {
    if (timestamp <= 0) return '尚未更新';
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    String two(int value) => value.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}';
  }
}

/// 任務列右側的圓形控制鈕（暫停、繼續、重試）。
class _TaskControlButton extends StatelessWidget {
  const _TaskControlButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        excludeSemantics: true,
        child: PressScale(
          onTap: onPressed,
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.primary.withValues(alpha: 0.12),
            ),
            child: Icon(icon, size: 20, color: scheme.primary),
          ),
        ),
      ),
    );
  }
}
