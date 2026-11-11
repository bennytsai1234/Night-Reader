import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:night_reader/core/ai_repair/ai_repair_session.dart';
import 'package:night_reader/core/ai_repair/ai_repair_settings.dart';
import 'package:night_reader/core/ai_repair/source_repair_batch.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/widgets/app_dialogs.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/glass_menu.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';

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
      when current.sourceUrl == source.bookSourceUrl) {
    await navigator.push(
      MaterialPageRoute<void>(builder: (_) => current.page()),
    );
    return;
  }
  // 一次一件：別的工作在跑時入口是灰的，這裡再擋一次。
  if (!backgroundWorkIdle()) return;
  final service = await (settings ?? AiRepairSettings()).service();
  if (!context.mounted) return;
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
        // 剪貼簿要使用者來回貼，留在這一頁：返回等於停止。
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
  // 一個書源也照整批修復每個網站的上限：模型一直回讀不懂的話不會一直花下去。
  var tokens = 0;
  final session = AiRepairSession(
    source: source,
    service: service,
    hasBudget: () => tokens < SourceRepairBatch.defaultSiteTokenBudget,
    onUsage: (usage) => tokens += usage.prompt + usage.completion,
  );
  final run = SingleRepairRun(session);
  repairs.adopt(run);
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

  /// 剪貼簿的修復：這一頁開始並收掉 [session]，返回等於停止。整批修復點進
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

  AiRepairSession get _session => widget.session;

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

  /// 自己啟動的修復先停止並等執行中工作退出，才能從頁面返回。
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
      ..showSnackBar(SnackBar(content: Text(message)));
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

  Future<void> _copyTranscript() async {
    await Clipboard.setData(ClipboardData(text: _session.transcript));
    if (mounted) _say('已複製紀錄');
  }

  @override
  Widget build(BuildContext context) {
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
                      label: 'AI 修書源設定',
                    ),
                    GlassMenuItem(
                      value: 'copy',
                      icon: Icons.copy_rounded,
                      label: '複製紀錄',
                      enabled: _session.hasTranscript,
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
                        unawaited(_copyTranscript());
                    }
                  },
                ),
              ],
            ),
            body: GroupedListView(
              children: [
                if (job.steps.isNotEmpty) ...[
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
                    ],
                  ),
                  if (job.awaitingPaste)
                    GroupedSection(
                      children: [
                        GroupedTextFieldRow(
                          controller: _paste,
                          hintText: '貼上 AI 回的書源 JSON',
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
                GroupedSection(
                  children: [
                    if (_session.isFinished)
                      GroupedRow(
                        title: '完成',
                        accent: true,
                        showChevron: false,
                        onTap: () => Navigator.of(context).maybePop(),
                      )
                    else
                      GroupedRow(
                        title: _session.isStopped ? '正在停下…' : '停止',
                        destructive: true,
                        showChevron: false,
                        onTap: _session.isStopped ? null : _session.stop,
                      ),
                  ],
                ),
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
          child: Text(
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
