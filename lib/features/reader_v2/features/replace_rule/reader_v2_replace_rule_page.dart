import 'package:flutter/material.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/core/database/dao/replace_rule_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/replace_rule.dart';
import 'package:night_reader/features/reader_v2/features/replace_rule/reader_v2_replace_rule_editor_sheet.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/context_ext.dart';
import 'package:night_reader/shared/widgets/app_dialogs.dart';
import 'package:night_reader/shared/widgets/app_state_view.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/glass_menu.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:night_reader/shared/widgets/swipe_actions.dart';

class ReaderV2ReplaceRulePage extends StatefulWidget {
  const ReaderV2ReplaceRulePage({super.key});

  @override
  State<ReaderV2ReplaceRulePage> createState() =>
      _ReaderV2ReplaceRulePageState();
}

class _ReaderV2ReplaceRulePageState extends State<ReaderV2ReplaceRulePage> {
  final ReplaceRuleDao _replaceDao = getIt<ReplaceRuleDao>();
  bool _loading = true;
  Object? _loadError;
  List<ReplaceRule> _rules = const <ReplaceRule>[];

  @override
  void initState() {
    super.initState();
    _loadRules();
  }

  Future<void> _loadRules() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final rules = await _replaceDao.getAll();
      if (!mounted) return;
      setState(() {
        _rules = rules;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = error;
      });
    }
  }

  Future<void> _openEditor({ReplaceRule? rule}) async {
    await ReaderV2ReplaceRuleEditorSheet.show(
      context,
      rule: rule,
      onSave: (next) async {
        if (next.id == 0) {
          next.order = _rules.length;
        }
        await _replaceDao.upsert(next);
      },
    );
    if (mounted) await _loadRules();
  }

  Future<void> _deleteRule(ReplaceRule rule) async {
    try {
      await _replaceDao.deleteById(rule.id);
      await _loadRules();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('刪除規則失敗：$error')));
    }
  }

  Future<void> _toggleEnabled(ReplaceRule rule, bool enabled) async {
    try {
      await _replaceDao.updateEnabled(rule.id, enabled);
      await _loadRules();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('更新規則狀態失敗：$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassNavHeader(
        title: '替換規則',
        actions: [
          GlassIconButton(
            onPressed: _loading || _loadError != null
                ? null
                : () => _openEditor(),
            icon: Icons.add_rounded,
            tooltip: '新增規則',
          ),
        ],
      ),
      body: Builder(builder: _buildBody),
    );
  }

  Widget _buildBody(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return Padding(
      padding: EdgeInsets.only(
        top: _loading || _loadError != null || _rules.isEmpty ? padding.top : 0,
      ),
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? AppStateView(
              icon: Icons.error_outline,
              title: '替換規則載入失敗',
              description: '無法讀取現有規則，請稍後再試。',
              tone: AppStateTone.error,
              primaryAction: AppStateAction(
                label: '重試',
                icon: Icons.refresh,
                onPressed: _loadRules,
              ),
            )
          : _rules.isEmpty
          ? AppStateView(
              icon: Icons.rule_rounded,
              title: '還沒有替換規則',
              description: '新增規則後，可在閱讀時自動整理標題或正文。',
              primaryAction: AppStateAction(
                label: '新增規則',
                icon: Icons.add,
                onPressed: _openEditor,
              ),
            )
          : SwipeActionsGroup(
              child: GroupedListView(
                children: [
                  GroupedSection(
                    topGap: AppSpacing.sm,
                    children: [
                      for (final rule in _rules) _buildRuleRow(context, rule),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildRuleRow(BuildContext context, ReplaceRule rule) {
    final chrome = AppChrome.of(context);
    final scheme = Theme.of(context).colorScheme;
    final content = Builder(
      builder: (rowContext) => InkWell(
        onTap: () => _openEditor(rule: rule),
        onLongPress: () => _showRuleMenu(rowContext, rule),
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
                      rule.name.isEmpty ? '未命名規則' : rule.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyBase.copyWith(
                        height: 1.3,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${rule.pattern} → ${rule.replacement}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySm.copyWith(
                        height: 1.3,
                        color: chrome.sectionText,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: [
                        _chip(context, rule.isEnabled ? '已啟用' : '已停用'),
                        _chip(context, rule.isRegex ? '正則' : '純文字'),
                        if (rule.scopeContent) _chip(context, '正文'),
                        if (rule.scopeTitle) _chip(context, '標題'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Semantics(
                label: '啟用 ${rule.name}',
                child: GroupedSwitch(
                  value: rule.isEnabled,
                  onChanged: (value) => _toggleEnabled(rule, value),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return SwipeActions(
      key: ValueKey(rule.id),
      trailing: [
        SwipeAction(
          label: '刪除',
          icon: Icons.delete_outline_rounded,
          color: context.danger,
          destructive: true,
          onPressed: () => _confirmDelete(rule),
        ),
      ],
      child: Material(color: chrome.groupedSurface, child: content),
    );
  }

  Future<void> _showRuleMenu(BuildContext rowContext, ReplaceRule rule) async {
    final action = await showGlassMenu<String>(
      context: rowContext,
      anchor: globalRectOf(rowContext),
      entries: [
        const GlassMenuItem(
          value: 'edit',
          label: '編輯規則',
          icon: Icons.edit_outlined,
        ),
        GlassMenuItem(
          value: 'toggle',
          label: rule.isEnabled ? '停用規則' : '啟用規則',
          icon: rule.isEnabled
              ? Icons.toggle_off_outlined
              : Icons.toggle_on_outlined,
        ),
        const GlassMenuDivider(),
        const GlassMenuItem(
          value: 'delete',
          label: '刪除',
          icon: Icons.delete_outline_rounded,
          destructive: true,
        ),
      ],
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'edit':
        await _openEditor(rule: rule);
      case 'toggle':
        await _toggleEnabled(rule, !rule.isEnabled);
      case 'delete':
        await _confirmDelete(rule);
    }
  }

  Widget _chip(BuildContext context, String label) {
    final chrome = AppChrome.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: chrome.sectionText.withValues(alpha: 0.1),
        borderRadius: AppRadius.cardXs,
      ),
      child: Text(
        label,
        style: AppTextStyles.labelXs.copyWith(
          height: 1.15,
          color: chrome.sectionText,
        ),
      ),
    );
  }

  Future<void> _confirmDelete(ReplaceRule rule) async {
    final confirmed = await showAppConfirm(
      context: context,
      title: '刪除規則',
      message: '確定刪除「${rule.name.isEmpty ? rule.pattern : rule.name}」？',
      confirmLabel: '刪除',
      destructive: true,
    );
    if (confirmed) {
      await _deleteRule(rule);
    }
  }
}
