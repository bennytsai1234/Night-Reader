import 'dart:async';

import 'package:flutter/material.dart';
import 'package:night_reader/core/ai_repair/ai_repair_session.dart';
import 'package:night_reader/core/ai_repair/ai_repair_settings.dart';
import 'package:night_reader/core/ai_repair/source_repair_batch.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/context_ext.dart';
import 'package:night_reader/shared/widgets/app_dialogs.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/glass_menu.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';

import 'ai_repair_page.dart';
import 'ai_repair_settings_page.dart';
import 'repair_runs.dart';

/// 修復一批書源（docs/design/screens.md「修復異常書源」）：已經有一批在修、
/// 或修完還沒看過結果時推回那一批（ADR 0058）；不然沒設定 AI 服務時先去設定，
/// 問整批的 AI 用量上限後開始新的一批。書源管理在一批修完時重讀清單。
Future<void> openSourceRepair(
  BuildContext context,
  List<BookSource> sources, {
  required String title,
  AiRepairSettings? settings,
  RepairRuns? runs,
}) async {
  final navigator = Navigator.of(context);
  final repairs = runs ?? RepairRuns.instance;
  if (repairs.current case final BatchRepairRun current) {
    await navigator.push(
      MaterialPageRoute<void>(builder: (_) => SourceRepairPage(run: current)),
    );
    return;
  }
  // 一次一件：別的工作在跑時入口是灰的，這裡再擋一次。
  if (sources.isEmpty || !backgroundWorkIdle()) return;
  final service = await (settings ?? AiRepairSettings()).service();
  if (!context.mounted) return;
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
  final budget = await showAppAlert<int>(
    context: context,
    title: title,
    message:
        '先重新校驗、檢查網站，網站不在了的不送 AI；同一個網站只問 AI 一次，'
        '每個網站最多用 ${_tokens(SourceRepairBatch.defaultSiteTokenBudget)}。\n\n'
        '整批的 AI 用量上限：',
    actions: const [
      AppAlertAction(label: '100 萬 token', value: 1000000, isDefault: true),
      AppAlertAction(label: '300 萬 token', value: 3000000),
      AppAlertAction(label: '不限', value: 0),
      AppAlertAction(label: '取消', value: -1),
    ],
  );
  if (budget == null || budget < 0) return;
  final run = BatchRepairRun(
    SourceRepairBatch(
      sources: sources,
      service: service,
      tokenBudget: budget == 0 ? null : budget,
    ),
    title: title,
  );
  repairs.adopt(run);
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

  /// 網站不在了的那組已經停用或刪除了（顯示在那組最後一列）。
  String? _goneHandled;

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

  @override
  Widget build(BuildContext context) {
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
                entriesBuilder: (_) => const [
                  GlassMenuItem(
                    value: 'settings',
                    icon: Icons.tune_rounded,
                    label: 'AI 修書源設定',
                  ),
                ],
                onSelected: (_) => unawaited(
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AiRepairSettingsPage(),
                    ),
                  ),
                ),
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
                  GroupedRow(
                    title: 'AI 用量',
                    value: _batch.tokenBudget == null
                        ? _tokens(_batch.tokensUsed)
                        : '${_tokens(_batch.tokensUsed)}／${_tokens(_batch.tokenBudget!)}',
                    showChevron: false,
                  ),
                ],
              ),
              ..._results(context),
              GroupedSection(
                children: [
                  if (_batch.isFinished)
                    GroupedRow(
                      title: '完成',
                      accent: true,
                      showChevron: false,
                      onTap: () => Navigator.of(context).maybePop(),
                    )
                  else
                    GroupedRow(
                      title: _batch.isStopped ? '正在停下…' : '停止',
                      destructive: true,
                      showChevron: false,
                      onTap: _batch.isStopped ? null : _batch.stop,
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// 這一段的副標：做著時是進度（和通知內文同一句），做完是結果。
  String? _stageDetail(RepairStage stage) {
    final current = _batch.stage;
    if (stage.index > current.index) return null;
    if (stage == current && !_batch.isFinished) {
      return repairStageProgress(_batch);
    }
    int n(RepairOutcome outcome) => _batch.count(outcome);
    return switch (stage) {
      RepairStage.checking => _counts([
        ('沒問題', n(RepairOutcome.healthy)),
        ('不修', n(RepairOutcome.skipped)),
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

  Widget _stageIcon(BuildContext context, RepairStage stage) {
    if (_batch.failedStage == stage) {
      return aiRepairStepIcon(context, AiRepairStepState.failed);
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
    final notFixed = of(const {RepairOutcome.notFixed});
    final rest = [
      ('重新校驗就沒問題了', _batch.count(RepairOutcome.healthy)),
      ('不用修（需要登入、驗證、只能下載或 AI 試過修不好）', _batch.count(RepairOutcome.skipped)),
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
      if (gone.isNotEmpty)
        GroupedSection(
          header: '網站不在了 · ${gone.length}',
          footer: '已標「網站失效」，搜尋與閱讀不會用到。',
          children: [
            for (final item in gone) _itemRow(item),
            if (_goneHandled case final done?)
              GroupedRow(title: done, showChevron: false)
            else ...[
              GroupedRow(
                title: '停用這 ${gone.length} 個',
                accent: true,
                showChevron: false,
                onTap: () => unawaited(_disable(gone)),
              ),
              GroupedRow(
                title: '刪除這 ${gone.length} 個',
                destructive: true,
                showChevron: false,
                onTap: () => unawaited(_delete(gone)),
              ),
            ],
          ],
        ),
      if (notFixed.isNotEmpty)
        GroupedSection(
          header: '沒修好 · ${notFixed.length}',
          children: [for (final item in notFixed) _itemRow(item)],
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

  Widget _itemRow(RepairItem item) {
    final session = item.session;
    return GroupedRow(
      title: item.source.bookSourceName,
      subtitle: item.detail,
      maxSubtitleLines: 2,
      showChevron: session != null,
      onTap: session == null ? null : () => _openSession(session),
    );
  }

  Future<void> _disable(List<RepairItem> items) async {
    await getIt<BookSourceDao>().updateEnabledByUrls([
      for (final item in items) item.source.bookSourceUrl,
    ], false);
    if (!mounted) return;
    setState(() => _goneHandled = '已停用');
    _say('已停用 ${items.length} 個書源');
  }

  Future<void> _delete(List<RepairItem> items) async {
    final ok = await showAppAlert<bool>(
      context: context,
      title: '刪除 ${items.length} 個書源？',
      message: '網站已經不在了。刪掉之後要再用得重新匯入。',
      actions: const [
        AppAlertAction(label: '刪除', value: true, destructive: true),
        AppAlertAction(label: '取消', value: false),
      ],
    );
    if (ok != true) return;
    await getIt<BookSourceDao>().deleteByUrls([
      for (final item in items) item.source.bookSourceUrl,
    ]);
    if (!mounted) return;
    setState(() => _goneHandled = '已刪除');
    _say('已刪除 ${items.length} 個書源');
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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
