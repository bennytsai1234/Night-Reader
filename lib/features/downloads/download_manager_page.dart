import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:night_reader/shared/widgets/text/ui_text.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:provider/provider.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book/book_extensions.dart';
import 'package:night_reader/core/chinese/chinese_display.dart';
import 'package:night_reader/core/download/download_service.dart';
import 'package:night_reader/core/models/download_task.dart';
import 'package:night_reader/core/models/source/book_source_logic.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/context_ext.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/widgets/popups/app_dialogs.dart';
import 'package:night_reader/shared/widgets/app_state_view.dart';
import 'package:night_reader/shared/widgets/glass/glass.dart';
import 'package:night_reader/shared/widgets/glass/glass_menu.dart';
import 'package:night_reader/shared/widgets/lists/grouped_list.dart';
import 'package:night_reader/shared/widgets/skeleton/grouped_list_skeleton.dart';
import 'package:night_reader/shared/widgets/skeleton/skeleton.dart';
import 'package:night_reader/shared/widgets/lists/swipe_actions.dart';
import 'package:night_reader/shared/widgets/text/drag_overflow_text.dart';
import 'package:night_reader/core/chinese/ui_language.dart';

enum _QueueAction { pauseAll, resumeAll, retryFailed, clearCompleted }

typedef _QueueShape = ({
  List<DownloadTask> tasks,
  bool paused,
  bool hasActive,
  bool hasRetryable,
  bool hasCompleted,
});

typedef _QueueSummary = ({
  int waiting,
  int running,
  int paused,
  int failed,
  int latestUpdate,
});

/// 進度與失敗數的用字照書的類別：小說寫章，漫畫寫話，有聲書寫集。
extension _CountWords on BookSourceKind {
  /// 數量後面的單位，例如「3 / 10 話」。
  String get unit => switch (this) {
    BookSourceKind.comic => '話',
    BookSourceKind.audio => '集',
    _ => '章',
  };

  /// 失敗原因裡「第 n 章」那一列的名稱。
  String get entryLabel => this == BookSourceKind.novel ? '章節' : unit;

  /// 失敗原因裡失敗數那一列的名稱。
  String get failedLabel => this == BookSourceKind.novel ? '失敗章節數' : '失敗$unit數';
}

/// DownloadManagerPage - 全域背景下載管理頁面
class DownloadManagerPage extends StatelessWidget {
  const DownloadManagerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final service = context.read<DownloadService>();
    return Selector<DownloadService, _QueueShape>(
      selector: (_, service) => (
        tasks: List<DownloadTask>.of(service.tasks),
        paused: service.isPaused,
        hasActive: service.tasks.any((task) => !task.isCompleted),
        hasRetryable: service.tasks.any(service.canRetry),
        hasCompleted: service.tasks.any((task) => task.isCompleted),
      ),
      // 任務會原地更新進度，清單只看身分與順序；進度由對應的列訂閱。
      shouldRebuild: (before, after) =>
          !listEquals(before.tasks, after.tasks) ||
          before.paused != after.paused ||
          before.hasActive != after.hasActive ||
          before.hasRetryable != after.hasRetryable ||
          before.hasCompleted != after.hasCompleted,
      builder: (context, queue, _) => _buildPage(context, service, queue),
    );
  }

  Widget _buildPage(
    BuildContext context,
    DownloadService service,
    _QueueShape queue,
  ) {
    final tasks = queue.tasks;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassNavHeader(
        title: '背景下載佇列',
        actions: [
          // 頁首右邊只有一顆，動作都收進「更多」（docs/design/components.md
          // 「左右各一顆」）；每一項都不能按時整顆停用（ADR 0059）。
          GlassMenuButton<_QueueAction>(
            enabled:
                queue.hasActive || queue.hasRetryable || queue.hasCompleted,
            entriesBuilder: (_) => [
              GlassMenuItem(
                value: service.isPaused
                    ? _QueueAction.resumeAll
                    : _QueueAction.pauseAll,
                label: service.isPaused ? '繼續全部' : '暫停全部',
                icon: service.isPaused
                    ? Icons.play_arrow_rounded
                    : Icons.pause_rounded,
                enabled: queue.hasActive,
              ),
              GlassMenuItem(
                value: _QueueAction.retryFailed,
                label: '重試失敗的',
                icon: Icons.refresh_rounded,
                enabled: queue.hasRetryable,
              ),
              GlassMenuItem(
                value: _QueueAction.clearCompleted,
                label: '清除已完成',
                icon: Icons.delete_sweep_outlined,
                enabled: queue.hasCompleted,
              ),
            ],
            // 選單開著時佇列可能變了：照選的那一項的方向做，從服務當下的
            // 任務挑，不用打開選單時的那一份。
            onSelected: (action) {
              final current = List<DownloadTask>.of(service.tasks);
              switch (action) {
                case _QueueAction.pauseAll:
                  if (!service.isPaused &&
                      current.any((task) => !task.isCompleted)) {
                    service.togglePause();
                  }
                case _QueueAction.resumeAll:
                  if (service.isPaused) service.togglePause();
                case _QueueAction.retryFailed:
                  for (final task in current.where(service.canRetry)) {
                    service.retryTask(task.bookUrl);
                  }
                case _QueueAction.clearCompleted:
                  for (final task in current.where((t) => t.isCompleted)) {
                    service.removeTask(task.bookUrl);
                  }
              }
            },
          ),
        ],
      ),
      body: tasks.isEmpty
          ? Padding(
              padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
              child: const AppStateView(
                icon: Icons.download_done_rounded,
                title: '沒有背景下載任務',
              ),
            )
          : SwipeActionsGroup(
              child: GroupedListView(
                children: [
                  _buildQueueSummary(),
                  GroupedSection(
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

  _QueueSummary _queueSummary(DownloadService service) {
    final tasks = service.tasks;
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

    return (
      waiting: waiting,
      running: running,
      paused: paused,
      failed: failed,
      latestUpdate: latestUpdate,
    );
  }

  Widget _buildQueueSummary() => _Subscribed<_QueueSummary>(
    select: _queueSummary,
    builder: (context, summary) => GroupedSection(
      // 清單的第一組：包在訂閱裡，清單換不到它的上方間距，這裡照清單第一組
      // 給 0（[GroupedListView]）。
      topGap: 0,
      children: [
        GroupedContent(
          child: _SummaryStats([
            ('等待', summary.waiting),
            ('下載中', summary.running),
            ('暫停', summary.paused),
            ('失敗', summary.failed),
          ]),
        ),
        GroupedRow(
          title: '最近任務更新',
          value: _formatTimestamp(summary.latestUpdate),
          translateValue: false,
        ),
      ],
    ),
  );

  Widget _buildTaskTile(
    BuildContext context,
    DownloadService service,
    DownloadTask task,
    int index,
    int taskCount,
  ) => _Subscribed<(bool, int, int, int, int, String?, bool)>(
    // 列的狀態跟著書走，上移、下移時整列一起搬。
    key: ValueKey(task.bookUrl),
    // 任務是可變物件，取值而不是取物件本身，才能辨認哪一列有變。
    select: (service) => (
      service.isPaused,
      task.totalCount,
      task.successCount,
      task.errorCount,
      task.status,
      task.failureSummary(unit: service.kindOf(task.bookUrl).unit),
      // 按了暫停的那一輪收尾完，鈕才換成重試。
      service.canRetry(task),
    ),
    builder: (context, _) =>
        _buildTaskContent(context, service, task, index, taskCount),
  );

  Widget _buildTaskContent(
    BuildContext context,
    DownloadService service,
    DownloadTask task,
    int index,
    int taskCount,
  ) {
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
    final canRetry = service.canRetry(task);
    // 「暫停全部」時進行中的任務其實停著，單本的暫停／繼續交給頁首的恢復全部。
    final globallyPaused = service.isPaused && active;
    final failureSummary = task.failureSummary(
      unit: service.kindOf(task.bookUrl).unit,
    );

    // 控制鈕一直在（ADR 0059）：全部暫停中、已完成時灰掉。
    final Widget control;
    if (canRetry && !globallyPaused) {
      control = _TaskControlButton(
        icon: Icons.refresh_rounded,
        tooltip: '重試',
        onPressed: () => service.retryTask(task.bookUrl),
      );
    } else {
      control = _TaskControlButton(
        icon: task.isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
        tooltip: task.isPaused ? '繼續' : '暫停',
        onPressed: globallyPaused || task.isCompleted
            ? null
            : () => task.isPaused
                  ? service.resumeTask(task.bookUrl)
                  : service.pauseTask(task.bookUrl),
      );
    }

    return SwipeActions(
      key: ValueKey(task.bookUrl),
      trailing: [
        SwipeAction(
          label: '刪除',
          icon: Icons.delete_outline_rounded,
          color: AppTint.rust.color,
          destructive: true,
          onPressed: () => _removeTask(context, service, task),
        ),
      ],
      child: _TaskRow(
        title: task.bookName,
        progress: progress,
        status: _statusText(
          task,
          service.kindOf(task.bookUrl).unit,
          globallyPaused: globallyPaused,
        ),
        statusColor: _statusColor(
          context,
          task,
          globallyPaused: globallyPaused,
        ),
        downloading: task.isDownloading && !globallyPaused,
        failure: failureSummary,
        control: control,
        onMenu: (rowContext) =>
            _showTaskMenu(rowContext, service, task, index, taskCount),
      ),
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
        GlassMenuItem(
          value: 'details',
          label: '查看失敗原因',
          icon: Icons.info_outline_rounded,
          enabled: task.failureSummary() != null,
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
        _showFailureDetails(context, task, service.kindOf(task.bookUrl));
        break;
      case 'delete':
        _removeTask(context, service, task);
        break;
    }
  }

  /// 刪除任務。書架上的書（本地書、有聲書除外）沒下載完的章，下次開 App
  /// 書架自動下載會再排回來（ADR 0008），不想下載要按暫停，所以刪的時候說
  /// 一聲留下什麼。
  Future<void> _removeTask(
    BuildContext context,
    DownloadService service,
    DownloadTask task,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    service.removeTask(task.bookUrl);
    if (task.isCompleted) return;
    final book = await getIt<BookDao>().getByUrl(task.bookUrl);
    if (book == null ||
        !book.isInBookshelf ||
        book.isLocal ||
        book.bookKind == BookSourceKind.audio) {
      return;
    }
    messenger.showSnackBar(
      const SnackBar(content: UiText('已刪除。書架上的書下次開 App 會再排回下載，不想下載請改按暫停')),
    );
  }

  void _showFailureDetails(
    BuildContext context,
    DownloadTask task,
    BookSourceKind kind,
  ) {
    final chrome = AppChrome.of(context);
    // [translate] 給 false 的是書名這類書的資料：照閱讀偏好轉換（ADR 0066）。
    Widget detailRow(String label, String value, {bool translate = true}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 提示框裡的字一律 15，標籤欄放得下五個字。
            SizedBox(
              width: 80,
              child: UiText(label, style: TextStyle(color: chrome.sectionText)),
            ),
            Expanded(child: UiText(value, translate: translate)),
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
          detailRow('書籍', context.zh(task.bookName), translate: false),
          detailRow('失敗類型', task.lastErrorReason ?? '下載失敗'),
          if (task.lastErrorChapterIndex != null)
            detailRow(
              kind.entryLabel,
              '第 ${task.lastErrorChapterIndex! + 1} ${kind.unit}',
            ),
          detailRow(kind.failedLabel, '${task.errorCount}'),
          detailRow('原因', task.lastErrorMessage ?? '未記錄詳細原因'),
        ],
      ),
      actions: const [
        AppAlertAction(label: '關閉', value: null, isDefault: true),
      ],
    );
  }

  /// [unit] 是這本書的數量單位（章、話、集）。
  String _statusText(
    DownloadTask task,
    String unit, {
    required bool globallyPaused,
  }) {
    if (task.isCompleted && task.errorCount == 0) {
      return '下載完成';
    }
    if (task.endedWithFailures) {
      // 還沒有目錄（例如抓目錄就失敗）時總數是 0，不寫「0/0 章」。
      if (task.totalCount <= 0) return '下載失敗';
      final failed = task.errorCount > 0 ? '，${task.errorCount} $unit失敗' : '';
      return '下載失敗：已下載 ${task.successCount}/${task.totalCount} $unit$failed';
    }
    if (globallyPaused) {
      return '已暫停全部 ${task.successCount}/${task.totalCount} $unit';
    }
    if (task.isPaused) {
      return '已暫停 ${task.successCount}/${task.totalCount} $unit';
    }
    if (task.isWaiting) {
      return '等待中 ${task.successCount}/${task.totalCount} $unit';
    }
    return '${task.successCount} / ${task.totalCount} $unit';
  }

  Color _statusColor(
    BuildContext context,
    DownloadTask task, {
    required bool globallyPaused,
  }) {
    // 失敗時這一行只寫進度，用一般字色；危險色只給下一行的原因。
    if (task.endedWithFailures) return AppChrome.of(context).sectionText;
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

/// 只在 [select] 從下載服務取出的值變了才重建的一項（[Selector]）。骨架照
/// 現在的值建出來的那一項算，只讀不訂閱。
class _Subscribed<T> extends StatelessWidget implements GroupedSkeletonItem {
  const _Subscribed({super.key, required this.select, required this.builder});

  final T Function(DownloadService service) select;
  final Widget Function(BuildContext context, T value) builder;

  @override
  GroupedItemShape skeletonShape(
    BuildContext context, {
    required double width,
  }) => GroupedItemShape.of(
    builder(context, select(context.read<DownloadService>())),
    context: context,
    width: width,
  );

  @override
  Widget build(BuildContext context) => Selector<DownloadService, T>(
    selector: (_, service) => select(service),
    builder: (context, value, _) => builder(context, value),
  );
}

/// 佇列摘要：幾個狀態並排，等寬，數字下面一行標籤。
class _SummaryStats extends StatelessWidget implements GroupedSkeletonItem {
  const _SummaryStats(this.stats);

  final List<(String, int)> stats;

  static const TextStyle _valueStyle = AppTextStyles.titleMd;
  static const TextStyle _labelStyle = AppTextStyles.uiXs;

  /// 每一格的數字與標籤照字置中排，整列取最高的一格、各格垂直置中。
  @override
  GroupedItemShape skeletonShape(
    BuildContext context, {
    required double width,
  }) {
    final cellWidth = width / stats.length;
    final cells = [
      for (final (label, value) in stats)
        (
          GroupedItemShape.text(
            context,
            '$value',
            style: _valueStyle,
            width: cellWidth,
          ).centeredIn(cellWidth),
          GroupedItemShape.text(
            context,
            label,
            style: _labelStyle,
            width: cellWidth,
          ).centeredIn(cellWidth),
        ),
    ];
    final height = cells
        .map((cell) => cell.$1.height + cell.$2.height)
        .reduce(math.max);
    return GroupedItemShape(
      height,
      marks: [
        for (final (index, (value, label)) in cells.indexed) ...[
          ...value.marksAt(
            Offset(
              index * cellWidth,
              (height - value.height - label.height) / 2,
            ),
          ),
          ...label.marksAt(
            Offset(
              index * cellWidth,
              (height + value.height - label.height) / 2,
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chrome = AppChrome.of(context);
    return Row(
      children: [
        for (final (label, value) in stats)
          Expanded(
            child: Semantics(
              label: context.ui('$label $value'),
              excludeSemantics: true,
              child: Column(
                children: [
                  UiText(
                    '$value',
                    style: _valueStyle.copyWith(color: scheme.onSurface),
                  ),
                  UiText(
                    label,
                    style: _labelStyle.copyWith(color: chrome.sectionText),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// 一個下載任務：書名、進度條、狀態與失敗原因，右側是控制鈕。
class _TaskRow extends StatelessWidget implements GroupedSkeletonItem {
  const _TaskRow({
    required this.title,
    required this.progress,
    required this.status,
    required this.statusColor,
    required this.downloading,
    required this.failure,
    required this.control,
    required this.onMenu,
  });

  final String title;
  final double progress;
  final String status;
  final Color statusColor;

  /// 狀態右側寫「正在下載…」。
  final bool downloading;
  final String? failure;
  final Widget? control;
  final ValueChanged<BuildContext> onMenu;

  static const EdgeInsets _padding = EdgeInsets.symmetric(
    horizontal: AppGrouped.rowPadding,
    vertical: AppSpacing.md,
  );
  static const double _progressHeight = 4;
  static const String _downloadingText = '正在下載…';
  static final TextStyle _titleStyle = AppTextStyles.bodyBase.copyWith(
    height: 1.3,
    fontWeight: FontWeight.w500,
  );
  static final TextStyle _smallStyle = AppTextStyles.bodySm.copyWith(
    height: 1.3,
  );

  /// 書名、狀態與失敗原因照字排（進度條很細，骨架不畫），控制鈕一塊；
  /// 左邊一欄與控制鈕垂直置中。
  @override
  GroupedItemShape skeletonShape(
    BuildContext context, {
    required double width,
  }) {
    final inner = width - _padding.horizontal;
    final controlShape = switch (control) {
      final control? => groupedPartShape(control, context),
      null => null,
    };
    final textWidth = switch (controlShape) {
      final shape? => inner - AppSpacing.md - shape.width!,
      null => inner,
    };
    final title = GroupedItemShape.text(
      context,
      this.title,
      style: _titleStyle,
      width: textWidth,
      maxLines: 2,
    );
    final downloading = this.downloading
        ? GroupedItemShape.text(
            context,
            _downloadingText,
            style: _smallStyle,
            width: double.infinity,
          )
        : null;
    final status = GroupedItemShape.text(
      context,
      this.status,
      style: _smallStyle,
      width: switch (downloading) {
        final shape? => textWidth - AppSpacing.md - shape.width!,
        null => textWidth,
      },
      maxLines: 2,
    );
    final failure = switch (this.failure) {
      final text? => GroupedItemShape.text(
        context,
        text,
        style: _smallStyle,
        width: textWidth,
        maxLines: 2,
      ),
      null => null,
    };
    final statusTop =
        title.height + AppSpacing.sm + _progressHeight + AppSpacing.sm;
    final statusHeight = math.max(status.height, downloading?.height ?? 0);
    final failureTop = statusTop + statusHeight + AppSpacing.xs;
    final column = switch (failure) {
      final shape? => failureTop + shape.height,
      null => statusTop + statusHeight,
    };
    final row = math.max(column, controlShape?.height ?? 0);
    final columnTop = (row - column) / 2;
    return GroupedItemShape(
      row,
      marks: [
        ...title.marksAt(Offset(0, columnTop)),
        ...status.marksAt(Offset(0, columnTop + statusTop)),
        ...?downloading?.marksAt(
          Offset(textWidth - downloading.width!, columnTop + statusTop),
        ),
        ...?failure?.marksAt(Offset(0, columnTop + failureTop)),
        ...?controlShape?.marksAt(
          Offset(inner - controlShape.width!, (row - controlShape.height) / 2),
        ),
      ],
    ).padded(_padding);
  }

  @override
  Widget build(BuildContext context) {
    final chrome = AppChrome.of(context);
    final scheme = Theme.of(context).colorScheme;
    final control = this.control;
    final failure = this.failure;
    return Material(
      color: chrome.groupedSurface,
      child: Builder(
        builder: (rowContext) => InkWell(
          onTap: () => onMenu(rowContext),
          onLongPress: () => onMenu(rowContext),
          child: Padding(
            padding: _padding,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DragOverflowText(
                        // 書名，照閱讀偏好的繁簡轉換（ADR 0066）。
                        child: UiText(
                          context.zh(title),
                          translate: false,
                          maxLines: 2,
                          style: _titleStyle.copyWith(color: scheme.onSurface),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      ClipRRect(
                        borderRadius: AppRadius.pillShape,
                        child: LinearProgressIndicator(
                          value: progress,
                          backgroundColor: chrome.separator,
                          minHeight: _progressHeight,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: DragOverflowText(
                              child: UiText(
                                status,
                                maxLines: 2,
                                style: _smallStyle.copyWith(color: statusColor),
                              ),
                            ),
                          ),
                          if (downloading) ...[
                            const SizedBox(width: AppSpacing.md),
                            UiText(
                              _downloadingText,
                              style: _smallStyle.copyWith(
                                color: scheme.primary,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (failure != null) ...[
                        const SizedBox(height: AppSpacing.xs),
                        DragOverflowText(
                          child: UiText(
                            failure,
                            maxLines: 2,
                            style: _smallStyle.copyWith(color: context.danger),
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
      ),
    );
  }
}

/// 任務列右側的圓形控制鈕（暫停、繼續、重試）。
class _TaskControlButton extends StatelessWidget
    implements GroupedSkeletonItem {
  const _TaskControlButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;

  /// null 時灰掉、點了沒反應。
  final VoidCallback? onPressed;

  static const double _circle = 34;

  /// 點擊範圍裡置中的圓鈕一塊。
  @override
  GroupedItemShape skeletonShape(
    BuildContext context, {
    required double width,
  }) {
    const inset = (AppGlass.buttonSize - _circle) / 2;
    return GroupedItemShape(
      AppGlass.buttonSize,
      width: AppGlass.buttonSize,
      marks: [
        SkeletonShape(
          const Rect.fromLTWH(inset, inset, _circle, _circle),
          radius: BorderRadius.circular(_circle / 2),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 停用時強調色換回一般字色，整顆再降透明度（[AppDisabled]）。
    final tone = onPressed == null ? scheme.onSurface : scheme.primary;
    final label = context.ui(tooltip);
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        enabled: onPressed != null,
        // excludeSemantics 也排除了子樹手勢的點擊動作，要在這裡補上。
        onTap: onPressed,
        child: PressScale(
          onTap: onPressed,
          // 命中區放大到 44（設計系統的圓形按鈕尺寸），圓鈕維持 34 置中；
          // 點偏一點不會打開整列的選單。
          child: Opacity(
            opacity: onPressed == null ? AppDisabled.opacity : 1,
            child: SizedBox.square(
              dimension: AppGlass.buttonSize,
              child: Center(
                child: Container(
                  width: _circle,
                  height: _circle,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: tone.withValues(alpha: 0.12),
                  ),
                  child: Icon(icon, size: 20, color: tone),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
