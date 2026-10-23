import 'dart:math' as math;

import 'package:night_reader/core/exception/user_error.dart';
import 'package:flutter/material.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/core/database/dao/replace_rule_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/replace_rule.dart';
import 'package:night_reader/features/reader_v2/features/replace_rule/reader_v2_replace_rule_editor_sheet.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/app_dialogs.dart';
import 'package:night_reader/shared/widgets/app_state_view.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/glass_menu.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:night_reader/shared/widgets/grouped_list_skeleton.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';
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
          .showSnackBar(SnackBar(content: Text(failureMessage('刪除規則', error))));
    }
  }

  Future<void> _toggleEnabled(ReplaceRule rule, bool enabled) async {
    try {
      await _replaceDao.updateEnabled(rule.id, enabled);
      await _loadRules();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failureMessage('更新規則狀態', error))));
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
    return SwipeActions(
      key: ValueKey(rule.id),
      trailing: [
        SwipeAction(
          label: '刪除',
          icon: Icons.delete_outline_rounded,
          color: AppTint.rust.color,
          destructive: true,
          onPressed: () => _confirmDelete(rule),
        ),
      ],
      child: _RuleRow(
        rule: rule,
        onTap: () => _openEditor(rule: rule),
        onMenu: (rowContext) => _showRuleMenu(rowContext, rule),
        onToggle: (value) => _toggleEnabled(rule, value),
      ),
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

/// 一條替換規則：名稱、規則內容與標籤，右側是啟用開關。
class _RuleRow extends StatelessWidget implements GroupedSkeletonItem {
  const _RuleRow({
    required this.rule,
    required this.onTap,
    required this.onMenu,
    required this.onToggle,
  });

  final ReplaceRule rule;
  final VoidCallback onTap;
  final ValueChanged<BuildContext> onMenu;
  final ValueChanged<bool> onToggle;

  static const EdgeInsets _padding = EdgeInsets.symmetric(
    horizontal: AppGrouped.rowPadding,
    vertical: AppSpacing.md,
  );
  static const double _patternGap = 2;
  static const double _chipGap = AppSpacing.xs;
  static const EdgeInsets _chipPadding = EdgeInsets.symmetric(
    horizontal: AppSpacing.xs,
    vertical: 2,
  );
  static final TextStyle _nameStyle = AppTextStyles.bodyBase.copyWith(
    height: 1.3,
  );
  static final TextStyle _patternStyle = AppTextStyles.bodySm.copyWith(
    height: 1.3,
    fontFamily: 'monospace',
  );
  static final TextStyle _chipStyle = AppTextStyles.labelXs.copyWith(
    height: 1.15,
  );

  String get _name => rule.name.isEmpty ? '未命名規則' : rule.name;
  String get _pattern => '${rule.pattern} → ${rule.replacement}';
  List<String> get _chips => [
    rule.isEnabled ? '已啟用' : '已停用',
    rule.isRegex ? '正則' : '純文字',
    if (rule.scopeContent) '正文',
    if (rule.scopeTitle) '標題',
  ];

  /// 名稱與規則內容照字排，標籤照字的寬度一個個排、放不下就換行（每個
  /// 標籤整塊畫），開關一塊；左邊一欄與開關垂直置中。
  @override
  GroupedItemShape skeletonShape(
    BuildContext context, {
    required double width,
  }) {
    final inner = width - _padding.horizontal;
    final textWidth = inner - AppSpacing.md - GroupedSwitch.trackWidth;
    final name = GroupedItemShape.text(
      context,
      _name,
      style: _nameStyle,
      width: textWidth,
      maxLines: 1,
    );
    final pattern = GroupedItemShape.text(
      context,
      _pattern,
      style: _patternStyle,
      width: textWidth,
      maxLines: 2,
    );
    final chipsTop = name.height + _patternGap + pattern.height + _chipGap;
    final chips = <SkeletonShape>[];
    var x = 0.0;
    var y = chipsTop;
    var runHeight = 0.0;
    for (final label in _chips) {
      final text = GroupedItemShape.textSize(
        context,
        label,
        style: _chipStyle,
        maxWidth: textWidth - _chipPadding.horizontal,
      );
      final size = Size(
        text.width + _chipPadding.horizontal,
        text.height + _chipPadding.vertical,
      );
      if (x > 0 && x + size.width > textWidth) {
        x = 0;
        y += runHeight + _chipGap;
        runHeight = 0;
      }
      chips.add(SkeletonShape(Offset(x, y) & size, radius: AppRadius.cardXs));
      x += size.width + _chipGap;
      runHeight = math.max(runHeight, size.height);
    }
    final column = y + runHeight;
    final row = math.max(column, GroupedSwitch.trackHeight);
    final columnTop = (row - column) / 2;
    return GroupedItemShape(
      row,
      marks: [
        ...name.marksAt(Offset(0, columnTop)),
        ...pattern.marksAt(Offset(0, columnTop + name.height + _patternGap)),
        for (final chip in chips)
          SkeletonShape(
            chip.rect.shift(Offset(0, columnTop)),
            radius: chip.radius,
          ),
        SkeletonShape(
          Rect.fromLTWH(
            inner - GroupedSwitch.trackWidth,
            (row - GroupedSwitch.trackHeight) / 2,
            GroupedSwitch.trackWidth,
            GroupedSwitch.trackHeight,
          ),
          radius: AppRadius.pillShape,
        ),
      ],
    ).padded(_padding);
  }

  @override
  Widget build(BuildContext context) {
    final chrome = AppChrome.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: chrome.groupedSurface,
      child: Builder(
        builder: (rowContext) => InkWell(
          onTap: onTap,
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
                      Text(
                        _name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _nameStyle.copyWith(color: scheme.onSurface),
                      ),
                      const SizedBox(height: _patternGap),
                      Text(
                        _pattern,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: _patternStyle.copyWith(
                          color: chrome.sectionText,
                        ),
                      ),
                      const SizedBox(height: _chipGap),
                      Wrap(
                        spacing: _chipGap,
                        runSpacing: _chipGap,
                        children: [
                          for (final label in _chips)
                            Container(
                              padding: _chipPadding,
                              decoration: BoxDecoration(
                                color: chrome.sectionText.withValues(
                                  alpha: 0.1,
                                ),
                                borderRadius: AppRadius.cardXs,
                              ),
                              child: Text(
                                label,
                                style: _chipStyle.copyWith(
                                  color: chrome.sectionText,
                                ),
                              ),
                            ),
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
                    onChanged: onToggle,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
