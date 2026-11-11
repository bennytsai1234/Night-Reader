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
import 'source_repair_page.dart';

/// 從書源管理開始 AI 修一個書源：有 AI 服務就推修復頁；沒有時問要去設定、
/// 複製給 AI 或取消（docs/design/screens.md「AI 修書源」）。傳回有沒有改到
/// 書源，書源管理據此重讀。一批書源用 [openSourceRepair]。
Future<bool> openAiRepair(
  BuildContext context,
  BookSource source, {
  AiRepairSettings? settings,
}) async {
  final navigator = Navigator.of(context);
  final service = await (settings ?? AiRepairSettings()).service();
  if (!context.mounted) return false;
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
        return false;
      case 'clipboard':
        break;
      default:
        return false;
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
  await navigator.push(
    MaterialPageRoute<void>(builder: (_) => AiRepairPage(session: session)),
  );
  return session.job.outcome == AiRepairOutcome.repaired ||
      session.job.restored;
}

/// 修復頁：一步一列；返回等於停止
/// （docs/design/screens.md「AI 修書源」）。
class AiRepairPage extends StatefulWidget {
  const AiRepairPage({super.key, required this.session, this.owned = true});

  final AiRepairSession session;

  /// 這一頁開始並收掉 [session]；整批修復點進一個網站看步驟時是 false，
  /// 修復由整批修復管。
  final bool owned;

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
    if (!widget.owned) return;
    // 推入動畫播完再開始：校驗與試抓開 worker，不和轉場疊在一起（ADR 0018）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context)?.animation;
      if (route == null || route.isCompleted) {
        unawaited(_session.start());
        return;
      }
      void begin(AnimationStatus status) {
        if (status != AnimationStatus.completed) return;
        route.removeStatusListener(begin);
        if (mounted) unawaited(_session.start());
      }

      route.addStatusListener(begin);
    });
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
    if (widget.owned) _session.dispose();
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
