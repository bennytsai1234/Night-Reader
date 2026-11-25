import 'dart:convert';
import 'dart:math' as math;

import 'package:night_reader/core/exception/user_error.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:flutter/services.dart';
import 'package:night_reader/shared/widgets/text/ui_text.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/core/database/dao/replace_rule_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/replace_rule.dart';
import 'package:night_reader/core/diagnostics/app_log_service.dart';
import 'package:night_reader/core/sync/replace_rule_sync.dart';
import 'package:night_reader/shared/navigation/transition_settled.dart';
import 'package:night_reader/shared/layout/readable_width.dart';
import 'package:night_reader/features/reader/features/replace_rule/reader_replace_rule_editor_sheet.dart';
import 'package:night_reader/features/reader/features/replace_rule/reader_replace_rule_select_bar.dart';
import 'package:night_reader/features/replace_rule/replace_rule_exchange.dart';
import 'package:night_reader/shared/share_json_file.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/popups/app_dialogs.dart';
import 'package:night_reader/shared/widgets/app_state_view.dart';
import 'package:night_reader/shared/widgets/glass/glass.dart';
import 'package:night_reader/shared/widgets/glass/glass_menu.dart';
import 'package:night_reader/shared/widgets/lists/grouped_list.dart';
import 'package:night_reader/shared/widgets/lists/search_field.dart';
import 'package:night_reader/shared/widgets/lists/selection_circle.dart';
import 'package:night_reader/shared/widgets/lists/trailing_swap.dart';
import 'package:night_reader/shared/widgets/skeleton/grouped_list_skeleton.dart';
import 'package:night_reader/shared/widgets/skeleton/skeleton.dart';
import 'package:night_reader/shared/widgets/lists/swipe_actions.dart';
import 'package:night_reader/shared/widgets/text/drag_overflow_text.dart';
import 'package:night_reader/core/chinese/ui_language.dart';

class ReaderReplaceRulePage extends StatefulWidget {
  const ReaderReplaceRulePage({super.key});

  @override
  State<ReaderReplaceRulePage> createState() => _ReaderReplaceRulePageState();
}

class _ReaderReplaceRulePageState extends State<ReaderReplaceRulePage> {
  final ReplaceRuleDao _replaceDao = getIt<ReplaceRuleDao>();
  final TextEditingController _searchController = TextEditingController();
  bool _loading = true;
  Object? _loadError;
  List<ReplaceRule> _rules = const <ReplaceRule>[];
  String _searchQuery = '';

  /// 多選：進入時先把長按的那一條選起來；清單重讀後把已經不在的編號清掉。
  bool _editMode = false;
  final Set<int> _selectedIds = {};

  bool get _editing => _editMode && _rules.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadRules();
    ReplaceRuleSync.applied.addListener(_rulesSynced);
  }

  @override
  void dispose() {
    ReplaceRuleSync.applied.removeListener(_rulesSynced);
    _searchController.dispose();
    super.dispose();
  }

  bool _syncReloadPending = false;

  /// 同步套用了另一台的規則：安靜地重讀清單。被別的頁面蓋著時等露出來才
  /// 讀，不疊在換頁動畫上（ADR 0018）。
  Future<void> _rulesSynced() async {
    if (_syncReloadPending) return;
    _syncReloadPending = true;
    await TransitionSettled.uncovered(context);
    _syncReloadPending = false;
    if (!mounted) return;
    await _refreshRules();
  }

  /// 改了規則（新增、編輯、刪除、切換啟用、置頂置底、多選、同步）之後
  /// 重讀：清單留在畫面上，讀到了直接換內容，不回到載入中。
  Future<void> _refreshRules() async {
    try {
      final rules = await _replaceDao.getAll();
      if (!mounted) return;
      setState(() {
        _rules = rules;
        _loadError = null;
        final ids = {for (final rule in rules) rule.id};
        _selectedIds.removeWhere((id) => !ids.contains(id));
        if (rules.isEmpty) _editMode = false;
      });
    } catch (error) {
      AppLog.e('重讀替換規則失敗', error: error);
    }
  }

  /// 第一次讀與失敗後按「重試」：讀到之前畫骨架。
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

  /// 搜尋框比對規則名稱與分組；分組篩選不做（R16、R17）。
  List<ReplaceRule> get _visibleRules {
    final query = _searchQuery.toLowerCase();
    if (query.isEmpty) return _rules;
    return [
      for (final rule in _rules)
        if (rule.name.toLowerCase().contains(query) ||
            (rule.group ?? '').toLowerCase().contains(query))
          rule,
    ];
  }

  void _setSearchQuery(String value) {
    final query = value.trim();
    if (_searchQuery == query) return;
    setState(() => _searchQuery = query);
  }

  void _clearSearch() {
    _searchController.clear();
    _setSearchQuery('');
  }

  void _enterEditMode(ReplaceRule rule) {
    setState(() {
      _editMode = true;
      _selectedIds.add(rule.id);
    });
  }

  void _exitEditMode() {
    if (!_editMode && _selectedIds.isEmpty) return;
    setState(() {
      _editMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelected(ReplaceRule rule) {
    setState(() {
      if (!_selectedIds.remove(rule.id)) _selectedIds.add(rule.id);
    });
  }

  /// 目前清單上（有搜尋時只看符合的）全選；都選好了就全部取消。
  void _toggleSelectAll() {
    final visible = _visibleRules;
    if (visible.isEmpty) return;
    final allSelected = visible.every((rule) => _selectedIds.contains(rule.id));
    setState(() {
      if (allSelected) {
        _selectedIds.clear();
      } else {
        _selectedIds.addAll(visible.map((rule) => rule.id));
      }
    });
  }

  Future<void> _openEditor({ReplaceRule? rule}) async {
    await ReaderReplaceRuleEditorSheet.show(
      context,
      rule: rule,
      onSave: (next) async {
        if (next.id == 0) {
          await _replaceDao.append(next);
        } else {
          await _replaceDao.upsert(next);
        }
      },
    );
    if (mounted) await _refreshRules();
  }

  Future<void> _deleteRule(ReplaceRule rule) async {
    try {
      await _replaceDao.deleteById(rule.id);
      await _refreshRules();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: UiText(failureMessage('刪除規則', error))));
    }
  }

  Future<void> _toggleEnabled(ReplaceRule rule, bool enabled) async {
    try {
      await _replaceDao.updateEnabled(rule.id, enabled);
      await _refreshRules();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: UiText(failureMessage('更新規則狀態', error))),
      );
    }
  }

  Future<void> _moveRule(ReplaceRule rule, {required bool toTop}) async {
    try {
      if (toTop) {
        await _replaceDao.moveToTop(rule.id);
      } else {
        await _replaceDao.moveToBottom(rule.id);
      }
      await _refreshRules();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: UiText(failureMessage('移動規則', error))));
    }
  }

  Future<void> _setSelectedEnabled(bool enabled) async {
    final ids = _selectedIds.toList(growable: false);
    if (ids.isEmpty) return;
    try {
      await _replaceDao.updateEnabledByIds(ids, enabled);
      await _refreshRules();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: UiText(failureMessage(enabled ? '啟用規則' : '停用規則', error)),
        ),
      );
    }
  }

  /// 選中的規則，照套用的順序。
  List<ReplaceRule> get _selectedRules => [
    for (final rule in _rules)
      if (_selectedIds.contains(rule.id)) rule,
  ];

  /// 匯出選中：複製成 JSON（Legado 讀得懂，`encodeReplaceRules`）；太大放不進
  /// 剪貼簿時改用分享（同書源管理的「匯出選中」）。
  Future<void> _exportSelected() async {
    final rules = _selectedRules;
    if (rules.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    final json = encodeReplaceRules(rules);
    try {
      // Android Binder IPC 上限約 1 MB；超過時改走檔案分享。
      if (utf8.encode(json).length > 512 * 1024) {
        await _shareJson(json, rules);
        if (!mounted) return;
        messenger.showSnackBar(
          const SnackBar(content: UiText('規則過多，已改用分享方式匯出')),
        );
        return;
      }
      await Clipboard.setData(ClipboardData(text: json));
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: UiText('已複製至剪貼簿')));
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: UiText(failureMessage('匯出規則', error))),
      );
    }
  }

  /// 分享選中：存成 JSON 檔、用系統分享傳出去。
  Future<void> _shareSelected() async {
    final rules = _selectedRules;
    if (rules.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _shareJson(encodeReplaceRules(rules), rules);
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: UiText(failureMessage('分享規則', error))),
      );
    }
  }

  Future<void> _shareJson(String json, List<ReplaceRule> rules) =>
      shareJsonFile(
        json,
        fileName: rules.length == 1
            ? rules.single.name
            : 'export_${rules.length}_replace_rules',
        fallbackName: 'replaceRule',
        what: '替換規則',
      );

  @override
  Widget build(BuildContext context) {
    final editing = _editing;
    return PopScope<void>(
      canPop: !editing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exitEditMode();
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: _buildHeader(editing: editing),
        body: Builder(builder: _buildBody),
      ),
    );
  }

  /// 規則清單與多選工具列疊在一起：工具列浮在清單下緣，進出場只滑動、
  /// 不淡（ADR 0022，同書架的多選工具列）。
  Widget _buildBody(BuildContext context) {
    final inset = ReadableWidth.cardInsetOf(context);
    return Stack(
      children: [
        Positioned.fill(child: _buildRuleContent(context)),
        Positioned(
          left: inset.left,
          right: inset.right,
          bottom:
              MediaQuery.paddingOf(context).bottom + AppGlass.tabBarBottomGap,
          child: _buildSelectBar(context),
        ),
      ],
    );
  }

  /// 多選的工具列：進場照選單 200ms easeOutCubic、離場同長度 easeInCubic
  /// （同書架的多選工具列）；系統關閉動畫時直接出現、直接消失。
  Widget _buildSelectBar(BuildContext context) {
    final gap = MediaQuery.paddingOf(context).bottom + AppGlass.tabBarBottomGap;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : AppMotion.menu;
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: AppMotion.menuCurve,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => AnimatedBuilder(
        animation: animation,
        child: child,
        builder: (context, child) => GlassSlide(
          shown: animation.value,
          edge: AxisDirection.down,
          gap: gap,
          child: child!,
        ),
      ),
      child: _editing
          ? ReaderReplaceRuleSelectBar(
              key: const ValueKey('replace-rule-select-bar'),
              hasSelection: _selectedIds.isNotEmpty,
              onEnable: () => _setSelectedEnabled(true),
              onDisable: () => _setSelectedEnabled(false),
              onExport: _exportSelected,
              onShare: _shareSelected,
              onDelete: _confirmDeleteSelected,
            )
          : const SizedBox.shrink(
              key: ValueKey('replace-rule-select-bar-hidden'),
            ),
    );
  }

  GlassNavHeader _buildHeader({required bool editing}) {
    // 搜尋框一直在頁首下方（ADR 0059）：沒有規則時灰掉，讀取失敗也不給搜。
    final searchEnabled = !_loading && _loadError == null && _rules.isNotEmpty;
    final bottom = Padding(
      padding: const EdgeInsets.fromLTRB(
        AppGrouped.margin,
        0,
        AppGrouped.margin,
        AppGlass.headerGap,
      ),
      child: SearchField(
        controller: _searchController,
        hintText: '搜尋規則名稱、分組',
        glass: true,
        enabled: searchEnabled,
        onChanged: _setSearchQuery,
      ),
    );
    final bottomHeight = SearchField.height + AppGlass.headerGap;
    if (editing) {
      final visible = _visibleRules;
      final allSelected =
          visible.isNotEmpty &&
          visible.every((rule) => _selectedIds.contains(rule.id));
      return GlassNavHeader(
        morph: true,
        title: _selectedIds.isEmpty ? '選取規則' : '已選 ${_selectedIds.length} 項',
        // 同書源管理的多選：左全選、右完成（docs/design/components.md）。
        leading: GlassTextButton(
          label: allSelected ? '全不選' : '全選',
          onPressed: visible.isEmpty ? null : _toggleSelectAll,
        ),
        actions: [
          GlassTextButton(
            label: '完成',
            emphasized: true,
            onPressed: _exitEditMode,
          ),
        ],
        bottom: bottom,
        bottomHeight: bottomHeight,
      );
    }
    // 進出多選時標題淡換、兩側按鈕的玻璃留著只改大小（GlassMorph）。
    return GlassNavHeader(
      morph: true,
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
      bottom: bottom,
      bottomHeight: bottomHeight,
    );
  }

  Widget _buildRuleContent(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final visible = _visibleRules;
    final noResults = !_loading && _rules.isNotEmpty && visible.isEmpty;
    return Padding(
      padding: EdgeInsets.only(
        top: _loadError != null || (!_loading && (_rules.isEmpty || noResults))
            ? padding.top
            : 0,
      ),
      child: _loadError != null
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
          : !_loading && _rules.isEmpty
          ? AppStateView(
              icon: Icons.rule_rounded,
              title: '還沒有替換規則',
              primaryAction: AppStateAction(
                label: '新增規則',
                icon: Icons.add,
                onPressed: _openEditor,
              ),
            )
          : noResults
          ? AppStateView(
              icon: Icons.search_off,
              title: '找不到符合條件的規則',
              primaryAction: AppStateAction(
                label: '清除搜尋',
                icon: Icons.clear,
                onPressed: _clearSearch,
              ),
            )
          // 推入時只畫骨架（照幾條規則的樣子），讀到了先照真正的規則變一次
          // 形狀再換場（[GroupedListView.ready]）。
          : SwipeActionsGroup(
              child: GroupedListView(
                ready: !_loading,
                loadingLabel: '正在載入替換規則',
                // 多選時工具列浮在清單下緣，最後一條要留在它上面；和平常
                // 一樣再加上組間距。
                bottomPadding: _editing
                    ? AppGlass.tabBarBottomGap +
                          ReaderReplaceRuleSelectBar.height +
                          AppGrouped.sectionGap
                    : AppGrouped.sectionGap,
                children: [
                  GroupedSection(
                    separatorIndent: _editing
                        ? AppGrouped.rowPadding + _RuleRow.checkSlotWidth
                        : null,
                    children: [
                      if (_loading)
                        for (final rule in _placeholderRules)
                          _buildRuleRow(context, rule)
                      else
                        for (final rule in visible)
                          _buildRuleRow(context, rule),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  /// 載入中骨架照的幾條規則：只給骨架量形狀，不會顯示出來。
  static final List<ReplaceRule> _placeholderRules = [
    for (final (i, pattern) in const ['廣告文字', '本章未完', '最新章節網址'].indexed)
      ReplaceRule(id: -1 - i, name: '替換規則名稱', pattern: pattern),
  ];

  Widget _buildRuleRow(BuildContext context, ReplaceRule rule) {
    final editing = _editing;
    return SwipeActions(
      key: ValueKey(rule.id),
      enabled: !editing,
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
        editing: editing,
        isSelected: _selectedIds.contains(rule.id),
        onTap: () => editing ? _toggleSelected(rule) : _openEditor(rule: rule),
        onMenu: (rowContext) => _showRuleMenu(rowContext, rule),
        onToggle: (value) => _toggleEnabled(rule, value),
      ),
    );
  }

  Future<void> _showRuleMenu(BuildContext rowContext, ReplaceRule rule) async {
    final action = await showGlassMenu<String>(
      context: rowContext,
      anchor: globalRectOf(rowContext),
      // 編輯（點一下那一列）與啟用、停用（列尾的開關）列上就有；這裡放
      // 置頂、置底、選取與刪除，同書源的長按選單。
      entries: const [
        GlassMenuItem(
          value: 'top',
          label: '置頂',
          icon: Icons.vertical_align_top_rounded,
        ),
        GlassMenuItem(
          value: 'bottom',
          label: '置底',
          icon: Icons.vertical_align_bottom_rounded,
        ),
        GlassMenuItem(
          value: 'select',
          label: '選取',
          icon: Icons.check_circle_outline_rounded,
        ),
        GlassMenuDivider(),
        GlassMenuItem(
          value: 'delete',
          label: '刪除規則',
          icon: Icons.delete_outline_rounded,
          destructive: true,
        ),
      ],
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'top':
        await _moveRule(rule, toTop: true);
      case 'bottom':
        await _moveRule(rule, toTop: false);
      case 'select':
        _enterEditMode(rule);
      case 'delete':
        await _confirmDelete(rule);
    }
  }

  Future<void> _confirmDelete(ReplaceRule rule) async {
    final confirmed = await showAppConfirm(
      context: context,
      title: '刪除規則「${rule.name.isEmpty ? rule.pattern : rule.name}」？',
      confirmLabel: '刪除',
      destructive: true,
      irreversible: true,
    );
    if (confirmed) {
      await _deleteRule(rule);
    }
  }

  Future<void> _confirmDeleteSelected() async {
    final count = _selectedIds.length;
    if (count == 0) return;
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showAppConfirm(
      context: context,
      title: '刪除 $count 個規則？',
      confirmLabel: '刪除',
      destructive: true,
      irreversible: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await _replaceDao.deleteManyByIds(_selectedIds.toList(growable: false));
      if (!mounted) return;
      // 和書源管理的多選一樣留在選取，按「完成」才離開；全刪光時清單會
      // 自己結束多選。
      setState(() => _selectedIds.clear());
      await _refreshRules();
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: UiText('已刪除 $count 個規則')));
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: UiText(failureMessage('刪除規則', error))),
      );
    }
  }
}

/// 一條替換規則：名稱、規則內容與標籤，右側是啟用開關；多選時左側是
/// 勾選圈、列尾的開關收起來。
class _RuleRow extends StatelessWidget implements GroupedSkeletonItem {
  const _RuleRow({
    required this.rule,
    required this.editing,
    required this.isSelected,
    required this.onTap,
    required this.onMenu,
    required this.onToggle,
  });

  final ReplaceRule rule;
  final bool editing;
  final bool isSelected;
  final VoidCallback onTap;
  final ValueChanged<BuildContext> onMenu;
  final ValueChanged<bool> onToggle;

  /// 多選左側勾選圈佔用的寬度（圈 22 + 間距），和書源列一樣。
  static const double checkSlotWidth = 22 + AppGrouped.iconGap;

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
          onLongPress: editing ? null : () => onMenu(rowContext),
          child: Semantics(
            selected: editing ? isSelected : null,
            child: ColoredBox(
              color: isSelected && editing
                  ? scheme.primary.withValues(alpha: 0.06)
                  : Colors.transparent,
              child: Padding(
                padding: _padding,
                child: Row(
                  children: [
                    // 多選的勾選圈從左側滑入，收合時由外層裁切（同書源列）。
                    ClipRect(
                      child: AnimatedSize(
                        duration: AppMotion.spring,
                        curve: AppMotion.springCurve,
                        alignment: Alignment.centerLeft,
                        child: SizedBox(
                          width: editing ? checkSlotWidth : 0,
                          child: OverflowBox(
                            fit: OverflowBoxFit.deferToChild,
                            alignment: Alignment.centerLeft,
                            minWidth: checkSlotWidth,
                            maxWidth: checkSlotWidth,
                            child: SelectionCircle(selected: isSelected),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          DragOverflowText(
                            child: UiText(
                              rule.name.isEmpty ? context.ui(_name) : _name,
                              translate: false,
                              maxLines: 1,
                              style: _nameStyle.copyWith(
                                color: scheme.onSurface,
                              ),
                            ),
                          ),
                          const SizedBox(height: _patternGap),
                          DragOverflowText(
                            child: UiText(
                              _pattern,
                              translate: false,
                              maxLines: 2,
                              style: _patternStyle.copyWith(
                                color: chrome.sectionText,
                              ),
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
                                  child: UiText(
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
                    TrailingSwap(
                      child: editing
                          ? const SizedBox.shrink()
                          : Padding(
                              key: const ValueKey('enabled'),
                              padding: const EdgeInsets.only(
                                left: AppSpacing.md,
                              ),
                              child: Semantics(
                                label: '${context.ui('啟用')} ${rule.name}',
                                child: GroupedSwitch(
                                  value: rule.isEnabled,
                                  onChanged: onToggle,
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
