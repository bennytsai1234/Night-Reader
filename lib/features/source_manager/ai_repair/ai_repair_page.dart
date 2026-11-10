import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:night_reader/core/ai_repair/ai_repair_session.dart';
import 'package:night_reader/core/ai_repair/ai_repair_settings.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/context_ext.dart';
import 'package:night_reader/shared/widgets/app_dialogs.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/glass_menu.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';

import 'ai_repair_settings_page.dart';

/// 從書源管理開始 AI 修復：有 AI 服務就推修復頁；沒有時問要去設定、複製給
/// AI（只限一個書源）或取消（docs/design/screens.md「AI 修書源」）。傳回有沒有
/// 改到書源，書源管理據此重讀。
Future<bool> openAiRepair(
  BuildContext context,
  List<BookSource> sources, {
  AiRepairSettings? settings,
}) async {
  if (sources.isEmpty) return false;
  final navigator = Navigator.of(context);
  final service = await (settings ?? AiRepairSettings()).service();
  if (!context.mounted) return false;
  if (service == null) {
    final single = sources.length == 1;
    final choice = await showAppAlert<String>(
      context: context,
      title: single
          ? 'AI 修復「${sources.single.bookSourceName}」'
          : 'AI 修復 ${sources.length} 個書源',
      message: '還沒設定 AI 服務。',
      actions: [
        const AppAlertAction(
          label: '設定 AI 服務',
          value: 'settings',
          isDefault: true,
        ),
        if (single) const AppAlertAction(label: '複製給 AI', value: 'clipboard'),
        const AppAlertAction(label: '取消', value: 'cancel'),
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
  final session = AiRepairSession(sources: sources, service: service);
  await navigator.push(
    MaterialPageRoute<void>(builder: (_) => AiRepairPage(session: session)),
  );
  return session.count(AiRepairOutcome.repaired) > 0 ||
      session.jobs.any((job) => job.restored);
}

/// 修復頁：一個書源一張卡片，一步一列；返回等於停止
/// （docs/design/screens.md「AI 修書源」）。
class AiRepairPage extends StatefulWidget {
  const AiRepairPage({super.key, required this.session});

  final AiRepairSession session;

  @override
  State<AiRepairPage> createState() => _AiRepairPageState();
}

class _AiRepairPageState extends State<AiRepairPage> {
  final TextEditingController _paste = TextEditingController();

  AiRepairSession get _session => widget.session;

  @override
  void initState() {
    super.initState();
    // 推入動畫播完再開始：校驗與試抓開 worker，不和轉場疊在一起（ADR 0018）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
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

  @override
  void dispose() {
    _paste.dispose();
    _session.dispose();
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

  Future<void> _restore(AiRepairJob job) async {
    try {
      await _session.restore(job);
      if (mounted) _say('已還原「${job.original.bookSourceName}」');
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
        final jobs = _session.jobs;
        final batch = jobs.length > 1;
        final service = _session.service;
        final sentTo = service == null
            ? null
            : '送到 ${Uri.tryParse(service.baseUrl)?.host ?? service.baseUrl}'
                  ' · ${service.model}';
        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: GlassNavHeader(
            title: batch
                ? 'AI 修復 · ${jobs.length} 個書源'
                : 'AI 修復 · ${jobs.single.original.bookSourceName}',
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
                    enabled: _session.transcript.isNotEmpty,
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
              if (batch)
                GroupedSection(
                  footer: sentTo,
                  children: [
                    GroupedRow(
                      title: _session.isFinished
                          ? '修好 ${_session.count(AiRepairOutcome.repaired)} 個，'
                                '沒修好 ${_session.count(AiRepairOutcome.failed)} 個，'
                                '跳過 ${_session.count(AiRepairOutcome.skipped)} 個'
                          : '第 ${_session.current + 1}／${jobs.length} 個',
                      showChevron: false,
                    ),
                  ],
                ),
              for (final job in jobs)
                if (job.steps.isNotEmpty) ...[
                  GroupedSection(
                    header: batch ? job.original.bookSourceName : null,
                    footer: batch ? null : sentTo,
                    children: [
                      for (final step in job.steps)
                        GroupedRow(
                          leading: _stepIcon(context, step.state),
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
                  if (job.outcome case final outcome?
                      when outcome != AiRepairOutcome.skipped)
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
                      title: '停止',
                      destructive: true,
                      showChevron: false,
                      onTap: _session.stop,
                    ),
                ],
              ),
            ],
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
            onTap: () => unawaited(_restore(job)),
          ),
      ],
    );
  }
}

Widget _stepIcon(BuildContext context, AiRepairStepState state) =>
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
