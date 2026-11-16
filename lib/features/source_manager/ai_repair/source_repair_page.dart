import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:night_reader/shared/widgets/ui_text.dart';
import 'package:night_reader/core/ai_repair/ai_repair_session.dart';
import 'package:night_reader/core/ai_repair/ai_repair_settings.dart';
import 'package:night_reader/core/ai_repair/repair_batch_export.dart';
import 'package:night_reader/core/ai_repair/source_repair_batch.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/services/background_work/background_work.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/context_ext.dart';
import 'package:night_reader/shared/widgets/app_dialogs.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/glass_menu.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'ai_repair_page.dart';
import 'ai_repair_settings_page.dart';
import 'repair_runs.dart';

/// 修復一批書源（docs/design/screens.md「修復異常書源」）：已經有一批在修、
/// 或修完還沒看過結果時推回那一批（ADR 0058）；不然沒設定 AI 服務時先去設定，
/// 開始新的一批，AI 用量不設上限。書源管理在一批修完時重讀清單。
Future<void> openSourceRepair(
  BuildContext context,
  List<BookSource> sources, {
  required String title,
  AiRepairSettings? settings,
  RepairRuns? runs,
}) async {
  final navigator = Navigator.of(context);
  final repairs = runs ?? RepairRuns.instance;
  if (repairs.current case final BatchRepairRun current when !current.isDone) {
    await navigator.push(
      MaterialPageRoute<void>(builder: (_) => SourceRepairPage(run: current)),
    );
    return;
  }
  // 工作結束但結果還沒看過時，不能從另一個入口蓋掉它。
  if (sources.isEmpty || !repairs.canStartNew || !backgroundWorkIdle()) {
    return;
  }
  final aiSettings = settings ?? AiRepairSettings();
  final service = await aiSettings.service();
  final concurrency = await aiSettings.concurrency();
  if (!context.mounted || !repairs.canStartNew || !backgroundWorkIdle()) {
    return;
  }
  if (service == null) {
    final go = await showAppAlert<bool>(
      context: context,
      title: title,
      message: '還沒設定 AI 服務。',
      actions: const [
        AppAlertAction(label: '設定 AI 服務', value: true, isDefault: true),
        AppAlertAction(label: '取消', value: false),
      ],
    );
    if (go == true) {
      await navigator.push(
        MaterialPageRoute<void>(builder: (_) => const AiRepairSettingsPage()),
      );
    }
    return;
  }
  final run = BatchRepairRun(
    SourceRepairBatch(
      sources: sources,
      service: service,
      aiConcurrency: concurrency,
    ),
    title: title,
  );
  if (!repairs.adopt(run)) {
    run.disposeWork();
    run.dispose();
    return;
  }
  await navigator.push(
    MaterialPageRoute<void>(builder: (_) => SourceRepairPage(run: run)),
  );
}

String _tokens(int count) => count >= 10000
    ? '${(count / 10000).toStringAsFixed(count % 10000 == 0 ? 0 : 1)} 萬 token'
    : '$count token';

/// 整批修復頁：上面是四段進度與 AI 用量，下面照結果分組。返回時修復照跑，
/// 通知欄有進度（ADR 0058）。
class SourceRepairPage extends StatefulWidget {
  const SourceRepairPage({super.key, required this.run, this.autoStart = true});

  final BatchRepairRun run;

  /// 推入動畫播完就開始；截圖與測試傳 false。
  final bool autoStart;

  @override
  State<SourceRepairPage> createState() => _SourceRepairPageState();
}

class _SourceRepairPageState extends State<SourceRepairPage> {
  BatchRepairRun get _run => widget.run;
  SourceRepairBatch get _batch => _run.batch;

  /// 正在打包這批的紀錄：選單那一項先灰掉。
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _run.attach();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      _run.route = route;
      if (!widget.autoStart) return;
      // 推入動畫播完再開始：校驗開 worker，不和轉場疊在一起（ADR 0018）。
      final animation = route?.animation;
      if (animation == null || animation.isCompleted) {
        _run.start();
        return;
      }
      void begin(AnimationStatus status) {
        if (status != AnimationStatus.completed) return;
        animation.removeStatusListener(begin);
        if (mounted) _run.start();
      }

      animation.addStatusListener(begin);
    });
  }

  @override
  void dispose() {
    _run.detach();
    super.dispose();
  }

  void _openSession(AiRepairSession session) => unawaited(
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AiRepairPage(session: session, owned: false),
      ),
    ),
  );

  /// 暫停中按了繼續：照現在的 AI 服務設定，用同一批書源重開，已經有結果的
  /// 不再處理。
  Future<void> _resume() async {
    if (!_run.canResume) return;
    final service = await AiRepairSettings().service();
    if (!mounted) return;
    if (service == null) {
      final go = await showAppAlert<bool>(
        context: context,
        title: _run.title,
        message: '還沒設定 AI 服務。',
        actions: const [
          AppAlertAction(label: '設定 AI 服務', value: true, isDefault: true),
          AppAlertAction(label: '取消', value: false),
        ],
      );
      if (go == true && mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const AiRepairSettingsPage()),
        );
      }
      return;
    }
    await _run.resume();
  }

  /// 最後一張卡片：做著時「暫停｜結束」，暫停中「繼續｜結束」（使用者
  /// 2026-11-15 在 AI 找書的候選圖上選的甲，修書源照同一套），做完是「完成」。
  List<Widget> _controls() {
    if (_batch.isFinished) {
      return [
        GroupedRow(
          title: '完成',
          accent: true,
          showChevron: false,
          onTap: () => Navigator.of(context).maybePop(),
        ),
      ];
    }
    final ending = _batch.isStopped || _run.isEnding;
    final end = GroupedRow(
      title: ending ? backgroundWorkEnding : '結束',
      destructive: true,
      showChevron: false,
      onTap: ending ? null : () => unawaited(_run.end()),
    );
    if (_run.isPaused) {
      return [
        GroupedRow(
          title: '繼續',
          accent: true,
          showChevron: false,
          enabled: _run.canResume,
          onTap: _run.canResume ? () => unawaited(_resume()) : null,
        ),
        end,
      ];
    }
    final pausing = _batch.isPaused;
    return [
      GroupedRow(
        title: pausing ? backgroundWorkPausing : '暫停',
        showChevron: false,
        enabled: !pausing && !ending,
        onTap: pausing || ending ? null : _run.pauseNow,
      ),
      end,
    ];
  }

  @override
  Widget build(BuildContext context) {
    // 暫停後按繼續換成新的一批：先聽這一件，換了再聽新的那一批。
    return ListenableBuilder(
      listenable: _run,
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    return ListenableBuilder(
      listenable: _batch,
      builder: (context, _) {
        final service = _batch.service;
        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: GlassNavHeader(
            title: _run.title,
            actions: [
              GlassMenuButton<String>(
                entriesBuilder: (_) => [
                  const GlassMenuItem(
                    value: 'settings',
                    icon: Icons.tune_rounded,
                    label: 'AI 服務設定',
                  ),
                  GlassMenuItem(
                    value: 'export',
                    icon: Icons.ios_share_rounded,
                    label: '分享這批的全部紀錄',
                    enabled: !_exporting && _batch.items.any(_hasResult),
                  ),
                ],
                onSelected: (value) {
                  switch (value) {
                    case 'settings':
                      unawaited(
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const AiRepairSettingsPage(),
                          ),
                        ),
                      );
                    case 'export':
                      unawaited(_export());
                  }
                },
              ),
            ],
          ),
          body: GroupedListView(
            children: [
              GroupedSection(
                footer:
                    '送到 ${Uri.tryParse(service.baseUrl)?.host ?? service.baseUrl}'
                    ' · ${service.model}',
                children: [
                  for (final stage in repairStages)
                    GroupedRow(
                      leading: _stageIcon(context, stage),
                      title: repairStageTitle(stage),
                      subtitle: _stageDetail(stage),
                      showChevron: false,
                    ),
                  if (_run.isPaused)
                    GroupedRow(
                      leading: Icon(
                        Icons.pause_circle_rounded,
                        size: 22,
                        color: AppChrome.of(context).sectionText,
                      ),
                      title: '已暫停',
                      subtitle: '按「繼續」接著修，已經有結果的書源不再處理',
                      showChevron: false,
                    ),
                  GroupedRow(
                    title: 'AI 用量',
                    value: _tokens(_batch.tokensUsed),
                    showChevron: false,
                  ),
                ],
              ),
              ..._results(context),
              GroupedSection(children: _controls()),
            ],
          ),
        );
      },
    );
  }

  /// 這一段的副標：做著時是進度（和通知內文同一句），做完是結果。暫停中
  /// 每一段都寫目前的結果。
  String? _stageDetail(RepairStage stage) {
    final current = _batch.stage;
    final paused = _run.isPaused;
    if (!paused && stage.index > current.index) return null;
    if (!paused && stage == current && !_batch.isFinished) {
      return repairStageProgress(_batch);
    }
    int n(RepairOutcome outcome) => _batch.count(outcome);
    return switch (stage) {
      RepairStage.checking => _counts([
        ('沿用校驗結果', _batch.reusedChecks),
        ('沒問題', n(RepairOutcome.healthy)),
        ('不用修', n(RepairOutcome.skipped)),
        ('AI 之前修不好', n(RepairOutcome.aiUnfixable)),
      ]),
      RepairStage.checkingSites => _counts([
        ('網站不在了', n(RepairOutcome.siteGone)),
      ]),
      RepairStage.moving => _counts([('換好', n(RepairOutcome.moved))]),
      RepairStage.repairing => _counts([
        ('AI 修好', n(RepairOutcome.aiFixed)),
        ('套用到同網站', n(RepairOutcome.shared)),
      ]),
      RepairStage.sharing || RepairStage.done => null,
    };
  }

  /// 「沒問題 30 個，不修 2 個」：0 個的不寫，全是 0 時寫「沒有」。
  static String _counts(List<(String, int)> parts) {
    final shown = [
      for (final (label, count) in parts)
        if (count > 0) '$label $count 個',
    ];
    return shown.isEmpty ? '沒有' : shown.join('，');
  }

  /// 出錯或按了結束的那一步畫紅叉（同單一書源的 AI 修），後面的步驟沒做，
  /// 畫成還沒輪到。
  Widget _stageIcon(BuildContext context, RepairStage stage) {
    // 暫停中：接著做時從頭一段一段重新走（已經有結果的不再處理）。
    if (_run.isPaused) {
      return aiRepairStepIcon(context, AiRepairStepState.waiting);
    }
    final cut = _batch.failedStage ?? _batch.stoppedStage;
    if (cut != null && stage.index >= cut.index) {
      return aiRepairStepIcon(
        context,
        stage == cut ? AiRepairStepState.failed : AiRepairStepState.waiting,
      );
    }
    final current = _batch.stage;
    final state = stage.index < current.index || _batch.isFinished
        ? AiRepairStepState.done
        : stage == current
        ? AiRepairStepState.running
        : AiRepairStepState.waiting;
    return aiRepairStepIcon(context, state);
  }

  List<Widget> _results(BuildContext context) {
    List<RepairItem> of(Set<RepairOutcome> outcomes) => [
      for (final item in _batch.items)
        if (outcomes.contains(item.outcome)) item,
    ];
    final fixed = of(const {
      RepairOutcome.moved,
      RepairOutcome.aiFixed,
      RepairOutcome.shared,
    });
    final gone = of(const {RepairOutcome.siteGone});
    final goneLeft = _batch.goneLeft;
    final unstable = _batch.unstableItems;
    final unstableLeft = _batch.unstableLeft;
    final notFixed = of(const {RepairOutcome.notFixed})
        .where((item) => !unstable.contains(item))
        .toList();
    final skipped = of(const {RepairOutcome.skipped});
    final unfixable = of(const {RepairOutcome.aiUnfixable})
        .where((item) => !unstable.contains(item))
        .toList();
    final rest = [
      ('重新校驗就沒問題了', _batch.count(RepairOutcome.healthy)),
      ('沒輪到', _batch.count(RepairOutcome.notTried)),
    ].where((row) => row.$2 > 0).toList();
    final working = [
      for (final item in _batch.items)
        if (item.outcome == null && item.session != null) item,
    ];
    return [
      if (_batch.errorMessage case final error?)
        GroupedSection(
          children: [
            GroupedRow(
              title: '修復中斷',
              subtitle: error,
              maxSubtitleLines: 3,
              showChevron: false,
            ),
          ],
        ),
      if (working.isNotEmpty)
        GroupedSection(
          header: '正在修 · ${working.length}',
          children: [
            for (final item in working)
              GroupedRow(
                leading: aiRepairStepIcon(context, AiRepairStepState.running),
                translateTitle: false,
                title: item.source.bookSourceName,
                subtitle: _lastStep(item.session!),
                showChevron: true,
                onTap: () => _openSession(item.session!),
              ),
          ],
        ),
      if (fixed.isNotEmpty)
        GroupedSection(
          header: '修好了 · ${fixed.length}',
          children: [for (final item in fixed) _itemRow(item)],
        ),
      if (gone.isNotEmpty && goneLeft.isEmpty)
        GroupedSection(
          children: [
            GroupedRow(title: '網站不在了的 ${gone.length} 個已刪除', showChevron: false),
          ],
        )
      else if (goneLeft.isNotEmpty)
        GroupedSection(
          header: '網站不在了 · ${goneLeft.length}',
          footer: '已標「網站失效」',
          children: [
            for (final item in goneLeft) _itemRow(item),
            if (gone.length > goneLeft.length)
              GroupedRow(
                title: '已刪除 ${gone.length - goneLeft.length} 個',
                showChevron: false,
              ),
            GroupedRow(
              title: '刪除這 ${goneLeft.length} 個',
              destructive: true,
              showChevron: false,
              onTap: _batch.isEditing
                  ? null
                  : () => unawaited(_delete(goneLeft.length)),
            ),
          ],
        ),
      if (unstable.isNotEmpty && unstableLeft.isEmpty)
        GroupedSection(
          children: [
            GroupedRow(
              title: '網站不穩定的 ${unstable.length} 個已刪除',
              showChevron: false,
            ),
          ],
        )
      else if (unstableLeft.isNotEmpty)
        GroupedSection(
          header: '網站不穩定 · ${unstableLeft.length}',
          footer: '已判定無法修復，列為可移除',
          children: [
            for (final item in unstableLeft) _itemRow(item),
            if (unstable.length > unstableLeft.length)
              GroupedRow(
                title: '已刪除 ${unstable.length - unstableLeft.length} 個',
                showChevron: false,
              ),
            GroupedRow(
              title: '刪除這 ${unstableLeft.length} 個',
              destructive: true,
              showChevron: false,
              onTap: _batch.isEditing
                  ? null
                  : () =>
                        unawaited(_delete(unstableLeft.length, unstable: true)),
            ),
          ],
        ),
      if (notFixed.isNotEmpty)
        GroupedSection(
          header: '沒修好 · ${notFixed.length}',
          children: [for (final item in notFixed) _itemRow(item)],
        ),
      if (skipped.isNotEmpty)
        GroupedSection(
          header: '不用修',
          children: [for (final item in skipped) _nameRow(item)],
        ),
      if (unfixable.isNotEmpty)
        GroupedSection(
          header: 'AI 之前修不好',
          children: [for (final item in unfixable) _nameRow(item)],
        ),
      if (rest.isNotEmpty)
        GroupedSection(
          children: [
            for (final (title, count) in rest)
              GroupedRow(title: title, value: '$count 個', showChevron: false),
          ],
        ),
    ];
  }

  /// AI 現在做到哪一步，例如「第 3 輪：AI 改了搜尋，試抓中…」。
  static String? _lastStep(AiRepairSession session) {
    final step = session.job.steps.lastOrNull;
    if (step == null) return '準備中…';
    return step.detail == null ? step.title : '${step.title}：${step.detail}';
  }

  /// 只列名稱，點了看原因。
  Widget _nameRow(RepairItem item) => GroupedRow(
    translateTitle: false,
    title: item.source.bookSourceName,
    showChevron: true,
    onTap: () => unawaited(
      showAppAlert<void>(
        context: context,
        title: item.source.bookSourceName,
        translateTitle: false,
        message: item.detail ?? '',
        actions: const [
          AppAlertAction(label: '知道了', value: null, isDefault: true),
        ],
      ),
    ),
  );

  Widget _itemRow(RepairItem item) {
    final session = item.session;
    return GroupedRow(
      translateTitle: false,
      title: item.source.bookSourceName,
      subtitle: item.detail,
      maxSubtitleLines: 2,
      showChevron: session != null,
      onTap: session == null ? null : () => _openSession(session),
    );
  }

  Future<void> _delete(int count, {bool unstable = false}) async {
    final ok = await showAppAlert<bool>(
      context: context,
      title: '刪除 $count 個書源？',
      message: unstable
          ? '網站不穩定，已判定無法修復。刪掉之後要再用得重新匯入。'
          : '網站已經不在了。刪掉之後要再用得重新匯入。',
      actions: const [
        AppAlertAction(label: '刪除', value: true, destructive: true),
        AppAlertAction(label: '取消', value: false),
      ],
    );
    if (ok != true) return;
    if (unstable) {
      await _batch.deleteUnstable();
    } else {
      await _batch.deleteGone();
    }
    if (mounted) _say('已刪除 $count 個書源');
  }

  static bool _hasResult(RepairItem item) =>
      item.outcome != null || item.session != null;

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final file = await exportRepairBatch(
        _batch,
        title: _run.title,
        into: Directory(
          '${(await getTemporaryDirectory()).path}/repair-export',
        ),
      );
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/zip')],
          subject: '${_run.title}：全部紀錄',
        ),
      );
    } catch (error) {
      if (mounted) _say('打包紀錄失敗：$error');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: UiText(message)));
  }
}

/// 修復步驟的圖示：做完是綠色勾、做著是轉圈、失敗是紅色叉、還沒開始是空心圓。
Widget aiRepairStepIcon(BuildContext context, AiRepairStepState state) =>
    switch (state) {
      AiRepairStepState.done => Icon(
        Icons.check_circle_rounded,
        size: 22,
        color: context.success,
      ),
      AiRepairStepState.failed => Icon(
        Icons.cancel_rounded,
        size: 22,
        color: context.danger,
      ),
      AiRepairStepState.running => SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      AiRepairStepState.waiting => Icon(
        Icons.radio_button_unchecked_rounded,
        size: 22,
        color: AppChrome.of(context).sectionText,
      ),
    };
