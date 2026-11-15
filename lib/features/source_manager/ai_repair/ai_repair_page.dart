import 'dart:async';

import 'package:flutter/material.dart';
import 'package:night_reader/shared/widgets/ui_text.dart';
import 'package:flutter/services.dart';
import 'package:night_reader/core/ai_repair/ai_repair_session.dart';
import 'package:night_reader/core/ai_repair/ai_repair_settings.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/services/background_work/background_work.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/widgets/app_dialogs.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/glass_menu.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:share_plus/share_plus.dart';

import 'ai_repair_settings_page.dart';
import 'repair_runs.dart';
import 'source_repair_page.dart';

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

/// 修復頁：一步一列（docs/design/screens.md「AI 修書源」）。
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
    if (mounted && run.isPaused && !run.isEnding) _say('書源已經不在了，沒辦法接著修');
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
    final ending = _session.isStopped || (run?.isEnding ?? false);
    final end = GroupedRow(
      title: ending ? backgroundWorkEnding : '結束',
      destructive: true,
      showChevron: false,
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
    final pausing = _session.isPaused;
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
            : '送到 ${Uri.tryParse(service.baseUrl)?.host ?? service.baseUrl}'
                  ' · ${service.model}';
        return PopScope(
          canPop: !widget.owned || !_session.isRunning,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && widget.owned) unawaited(_stopAndClose());
          },
          child: Scaffold(
            extendBodyBehindAppBar: true,
            appBar: GlassNavHeader(
              title: 'AI 修復 · ${job.original.bookSourceName}',
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
                if (job.steps.isNotEmpty || (run?.isPaused ?? false)) ...[
                  GroupedSection(
                    footer: sentTo,
                    children: [
                      for (final step in job.steps)
                        GroupedRow(
                          leading: aiRepairStepIcon(context, step.state),
                          title: step.title,
                          subtitle: step.detail,
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

  Widget _result(
    BuildContext context,
    AiRepairJob job,
    AiRepairOutcome outcome,
  ) {
    final repaired = outcome == AiRepairOutcome.repaired;
    final explanation = job.explanation ?? (repaired ? '校驗通過，已套用。' : '書源沒有改。');
    return GroupedSection(
      header: repaired ? (job.restored ? '已還原成改前的版本' : '修好了') : '沒修好，書源沒有改',
      children: [
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
