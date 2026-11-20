import 'dart:async';

import 'package:flutter/material.dart';
import 'package:night_reader/core/background_work/work_phase.dart';
import 'package:night_reader/shared/widgets/text/ui_text.dart';
import 'package:flutter/services.dart';
import 'package:night_reader/core/ai_repair/ai_repair_session.dart';
import 'package:night_reader/core/ai_repair/ai_repair_step.dart';
import 'package:night_reader/core/ai_repair/ai_repair_settings.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/background_work/background_work.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/widgets/popups/app_dialogs.dart';
import 'package:night_reader/shared/widgets/glass/glass.dart';
import 'package:night_reader/shared/widgets/glass/glass_menu.dart';
import 'package:night_reader/shared/widgets/lists/grouped_list.dart';
import 'package:share_plus/share_plus.dart';

import 'ai_repair_settings_page.dart';
import 'repair_runs.dart';
import 'source_repair_page.dart';

import 'package:night_reader/core/chinese/ui_language.dart';

/// 從書源管理開始 AI 修一個書源：這個書源正在修、或修完還沒看過結果時推回
/// 那一頁（ADR 0058）；有 AI 服務就開始修、推修復頁，返回時照修；沒有時問要
/// 去設定、複製給 AI 或取消（docs/design/screens.md「AI 修書源」）。書源管理在
/// 修完、頁面關掉時重讀。一批書源用 [openSourceRepair]。
Future<void> openAiRepair(
  BuildContext context,
  BookSource source, {
  AiRepairSettings? settings,
  RepairRuns? runs,
}) async {
  final navigator = Navigator.of(context);
  final repairs = runs ?? RepairRuns.instance;
  if (repairs.current case final SingleRepairRun current
      when !current.isDone && current.sourceUrl == source.bookSourceUrl) {
    await navigator.push(
      MaterialPageRoute<void>(builder: (_) => current.page()),
    );
    return;
  }
  // 工作結束但結果還沒看過時，不能從另一個入口蓋掉它。
  if (!repairs.canStartNew || !backgroundWorkIdle()) return;
  final service = await (settings ?? AiRepairSettings()).service();
  if (!context.mounted || !repairs.canStartNew || !backgroundWorkIdle()) {
    return;
  }
  if (service == null) {
    final choice = await showAppAlert<String>(
      context: context,
      title: 'AI 修復「${source.bookSourceName}」',
      message: '還沒設定 AI 服務。',
      actions: const [
        AppAlertAction(label: '設定 AI 服務', value: 'settings', isDefault: true),
        AppAlertAction(label: '複製給 AI', value: 'clipboard'),
        AppAlertAction(label: '取消', value: 'cancel'),
      ],
    );
    switch (choice) {
      case 'settings':
        await navigator.push(
          MaterialPageRoute<void>(builder: (_) => const AiRepairSettingsPage()),
        );
        return;
      case 'clipboard':
        // 剪貼簿要使用者來回貼，留在這一頁：返回等於結束。
        final session = AiRepairSession(source: source, service: null);
        await navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => AiRepairPage(session: session),
          ),
        );
        return;
      default:
        return;
    }
  }
  final session = AiRepairSession(source: source, service: service);
  final run = SingleRepairRun(session);
  if (!repairs.adopt(run)) {
    run.disposeWork();
    run.dispose();
    return;
  }
  await navigator.push(MaterialPageRoute<void>(builder: (_) => run.page()));
}

/// 修復頁：固定四段，AI 做過的步收在「經過」（docs/design/screens.md
/// 「AI 修書源」）。
class AiRepairPage extends StatefulWidget {
  const AiRepairPage({
    super.key,
    required this.session,
    this.owned = true,
    this.run,
  });

  final AiRepairSession session;

  /// 剪貼簿的修復：這一頁開始並收掉 [session]，返回等於結束。整批修復點進
  /// 一個網站看步驟時是 false，修復由整批修復管。
  final bool owned;

  /// 用 AI 服務的修復：由 [run] 在背景跑，這一頁開始它、返回時照修
  /// （ADR 0058）。
  final SingleRepairRun? run;

  @override
  State<AiRepairPage> createState() => _AiRepairPageState();
}

class _AiRepairPageState extends State<AiRepairPage> {
  final TextEditingController _paste = TextEditingController();
  bool _closing = false;

  /// 「經過」展開著：每次進這一頁都是收起的。
  bool _historyOpen = false;

  /// 背景跑的修復暫停後按繼續會換成新的一段，照 [AiRepairPage.run] 的。
  AiRepairSession get _session => widget.run?.session ?? widget.session;

  @override
  void initState() {
    super.initState();
    final run = widget.run;
    run?.attach();
    if (!widget.owned && run == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      run?.route = route;
      // 推入動畫播完再開始：校驗與試抓開 worker，不和轉場疊在一起（ADR 0018）。
      final animation = route?.animation;
      if (animation == null || animation.isCompleted) {
        _start();
        return;
      }
      void begin(AnimationStatus status) {
        if (status != AnimationStatus.completed) return;
        animation.removeStatusListener(begin);
        if (mounted) _start();
      }

      animation.addStatusListener(begin);
    });
  }

  void _start() {
    final run = widget.run;
    if (run != null) {
      run.start();
    } else {
      unawaited(_session.start());
    }
  }

  /// 自己啟動的修復先結束並等執行中工作退出，才能從頁面返回。
  Future<void> _stopAndClose() async {
    if (_closing) return;
    _closing = true;
    _session.stop();
    await _session.completion;
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _paste.dispose();
    widget.run?.detach();
    if (widget.owned && widget.run == null) _session.dispose();
    super.dispose();
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: UiText(message)));
  }

  Future<void> _submitPaste() async {
    FocusScope.of(context).unfocus();
    final problem = await _session.submitPaste(_paste.text);
    if (problem != null && mounted) _say(problem);
  }

  Future<void> _restore() async {
    try {
      final restored = await _session.restore();
      if (!mounted) return;
      _say(
        restored
            ? '已還原「${_session.job.original.bookSourceName}」'
            : '書源已經不在了，沒有還原',
      );
    } catch (error) {
      if (mounted) _say('還原失敗：$error');
    }
  }

  Future<void> _copySummary() async {
    await Clipboard.setData(ClipboardData(text: _session.log.summary));
    if (mounted) _say('已複製摘要');
  }

  Future<void> _shareFullLog() async {
    final file = await _session.log.file();
    if (file == null) {
      if (mounted) _say('完整紀錄沒有存成檔案');
      return;
    }
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/plain')],
        subject: 'AI 修復紀錄：${_session.job.original.bookSourceName}',
      ),
    );
  }

  /// 暫停中按了繼續：照現在的 AI 服務設定，這個書源從頭重修。
  Future<void> _resume(SingleRepairRun run) async {
    if (!run.canResume) return;
    final service = await AiRepairSettings().service();
    if (!mounted) return;
    if (service == null) {
      final go = await showAppAlert<bool>(
        context: context,
        title: 'AI 修復「${_session.job.original.bookSourceName}」',
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
    await run.resume();
    if (mounted && run.phase == WorkPhase.paused) _say('書源已經不在了，沒辦法接著修');
  }

  /// 最後一張卡片：背景跑的修復做著時「暫停｜結束」，暫停中「繼續｜結束」
  /// （使用者 2026-11-15 在 AI 找書的候選圖上選的甲，修書源照同一套）；剪貼簿
  /// 的修復只有「結束」；做完是「完成」。
  List<Widget> _controls(SingleRepairRun? run) {
    if (_session.isFinished && !(run?.isPaused ?? false)) {
      return [
        GroupedRow(
          title: '完成',
          accent: true,
          showChevron: false,
          onTap: () => Navigator.of(context).maybePop(),
        ),
      ];
    }
    // 背景跑的照頁面那層的階段；剪貼簿的修復沒有背景工作，照修復本身。
    final phase = run?.phase ?? _session.phase;
    final ending = phase == WorkPhase.ending;
    final end = GroupedRow(
      title: ending ? backgroundWorkEnding : '結束',
      destructive: true,
      showChevron: false,
      // 「正在結束…」不能再按，和停用的動作同一種灰。
      enabled: !ending,
      onTap: ending
          ? null
          : run == null
          ? _session.stop
          : () => unawaited(run.end()),
    );
    if (run == null) return [end];
    if (run.isPaused) {
      return [
        GroupedRow(
          title: '繼續',
          accent: true,
          showChevron: false,
          enabled: run.canResume,
          onTap: run.canResume ? () => unawaited(_resume(run)) : null,
        ),
        end,
      ];
    }
    final pausing = phase == WorkPhase.pausing;
    return [
      GroupedRow(
        title: pausing ? backgroundWorkPausing : '暫停',
        showChevron: false,
        enabled: !pausing && !ending,
        onTap: pausing || ending ? null : run.pauseNow,
      ),
      end,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final run = widget.run;
    if (run == null) return _build(context, null);
    return ListenableBuilder(
      listenable: run,
      builder: (context, _) => _build(context, run),
    );
  }

  Widget _build(BuildContext context, SingleRepairRun? run) {
    return ListenableBuilder(
      listenable: _session,
      builder: (context, _) {
        final job = _session.job;
        final service = _session.service;
        final sentTo = service == null
            ? null
            : '${Uri.tryParse(service.baseUrl)?.host ?? service.baseUrl}'
                  ' · ${service.model}';
        return PopScope(
          canPop: !widget.owned || !_session.isRunning,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && widget.owned) unawaited(_stopAndClose());
          },
          child: Scaffold(
            extendBodyBehindAppBar: true,
            appBar: GlassNavHeader(
              title: '${context.ui('AI 修復')} · ${job.original.bookSourceName}',
              translateTitle: false,
              actions: [
                GlassMenuButton<String>(
                  entriesBuilder: (_) => [
                    const GlassMenuItem(
                      value: 'settings',
                      icon: Icons.tune_rounded,
                      label: 'AI 服務設定',
                    ),
                    GlassMenuItem(
                      value: 'copy',
                      icon: Icons.copy_rounded,
                      label: '複製摘要',
                      enabled: _session.hasLog,
                    ),
                    GlassMenuItem(
                      value: 'share',
                      icon: Icons.ios_share_rounded,
                      label: '分享完整紀錄',
                      enabled: _session.hasLog,
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
                      case 'copy':
                        unawaited(_copySummary());
                      case 'share':
                        unawaited(_shareFullLog());
                    }
                  },
                ),
              ],
            ),
            body: GroupedListView(
              children: [
                if (!_clipboard || job.steps.isNotEmpty) ...[
                  GroupedSection(
                    children: [
                      ..._stageRows(context, job),
                      if (sentTo != null)
                        GroupedRow(
                          title: '送到',
                          value: sentTo,
                          translateValue: false,
                          showChevron: false,
                        ),
                      if (run?.isPaused ?? false)
                        GroupedRow(
                          leading: Icon(
                            Icons.pause_circle_rounded,
                            size: 22,
                            color: AppChrome.of(context).sectionText,
                          ),
                          title: '已暫停',
                          subtitle: '按「繼續」從頭重修這個書源',
                          showChevron: false,
                        ),
                    ],
                  ),
                  ?aiStepsHistory(
                    context,
                    steps: _history(job),
                    expanded: _historyOpen,
                    onToggle: () =>
                        setState(() => _historyOpen = !_historyOpen),
                  ),
                  if (job.awaitingPaste)
                    GroupedSection(
                      children: [
                        GroupedTextFieldRow(
                          controller: _paste,
                          hintText: '書源 JSON',
                          keyboardType: TextInputType.multiline,
                          minLines: 4,
                          maxLines: 8,
                        ),
                        GroupedRow(
                          title: '校驗並套用',
                          accent: true,
                          showChevron: false,
                          onTap: () => unawaited(_submitPaste()),
                        ),
                      ],
                    ),
                  if (job.outcome case final outcome?)
                    _result(context, job, outcome),
                ],
                GroupedSection(children: _controls(run)),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 剪貼簿的修復：照做過的步一步一列。只從「複製給 AI」進來，不進背景，
  /// 所以沒有 [AiRepairPage.run]；App 重開後還原的暫停修復也沒有 AI 服務，
  /// 但有 run，照固定四段畫。
  bool get _clipboard => widget.run == null && _session.usesClipboard;

  /// AI 修改規則那一段的每一步（AI 的輪與重新開始）。
  static List<AiRepairStep> _aiSteps(AiRepairJob job) => [
    for (final step in job.steps)
      if (step.kind != AiRepairStepKind.stage) step,
  ];

  /// 最後一次「校驗修好的書源」之後 AI 又做了事：交出的被退回，回到 AI 修改
  /// 規則，這次的校驗還沒開始。
  static bool _backToAi(AiRepairJob job) {
    final steps = job.steps;
    final verify = steps.lastIndexWhere((s) => s.title == aiRepairVerifyStage);
    return verify < 0 ||
        steps.lastIndexWhere((s) => s.kind != AiRepairStepKind.stage) > verify;
  }

  /// 「經過」：AI 做過的步，正在做的那一步寫在「AI 修改規則」的副標，不放進來。
  List<AiRepairStep> _history(AiRepairJob job) {
    final steps = _aiSteps(job);
    return _aiState(job, steps) == AiRepairStepState.running
        ? steps.sublist(0, steps.length - 1)
        : steps;
  }

  /// 「AI 修改規則」的狀態：還沒問 AI 是還沒開始；交出的正在校驗或校驗過了
  /// 是做完；AI 說修不好、出錯、按了暫停或結束時是失敗（後面的段沒做，同整批
  /// 修復）；其他時候是做著（兩輪之間、交出被退回後也算）。
  AiRepairStepState _aiState(AiRepairJob job, List<AiRepairStep> steps) {
    if (steps.isEmpty) return AiRepairStepState.waiting;
    if (!_backToAi(job)) return AiRepairStepState.done;
    if (steps.last.state == AiRepairStepState.running) {
      return AiRepairStepState.running;
    }
    if (job.outcome != null ||
        _session.phase == WorkPhase.pausing ||
        _session.phase == WorkPhase.paused) {
      return AiRepairStepState.failed;
    }
    return AiRepairStepState.running;
  }

  /// 卡片上的段：用 AI 服務時固定四段（校驗原本的書源、抓網頁、AI 修改規則、
  /// 校驗修好的書源），還沒輪到的畫空心圓；剪貼簿照做過的步一步一列。
  List<Widget> _stageRows(BuildContext context, AiRepairJob job) {
    GroupedRow row(AiRepairStepState state, String title, String? detail) =>
        GroupedRow(
          leading: aiRepairStepIcon(context, state),
          title: title,
          subtitle: detail,
          showChevron: false,
        );
    if (_clipboard) {
      return [
        for (final step in job.steps) row(step.state, step.title, step.detail),
      ];
    }
    GroupedRow stage(String title) {
      final step = job.steps.where((step) => step.title == title).lastOrNull;
      return step == null
          ? row(AiRepairStepState.waiting, title, null)
          : row(step.state, title, step.detail);
    }

    final ai = _aiSteps(job);
    return [
      stage(aiRepairCheckStage),
      stage(aiRepairFetchStage),
      row(_aiState(job, ai), 'AI 修改規則', ai.lastOrNull?.line),
      if (ai.isNotEmpty && _backToAi(job))
        row(AiRepairStepState.waiting, aiRepairVerifyStage, null)
      else
        stage(aiRepairVerifyStage),
    ];
  }

  Widget _result(
    BuildContext context,
    AiRepairJob job,
    AiRepairOutcome outcome,
  ) {
    final repaired = outcome == AiRepairOutcome.repaired;
    final explanation = job.explanation ?? (repaired ? '校驗通過，已套用。' : '書源沒有改。');
    return GroupedSection(
      children: [
        GroupedRow(
          title: repaired ? (job.restored ? '已還原成改前的版本' : '修好了') : '沒修好，書源沒有改',
          heading: true,
        ),
        GroupedContent(
          child: UiText(
            explanation,
            style: AppTextStyles.bodySm.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
        if (repaired && !job.restored)
          GroupedRow(
            title: '還原改前的版本',
            showChevron: false,
            onTap: () => unawaited(_restore()),
          ),
      ],
    );
  }
}
