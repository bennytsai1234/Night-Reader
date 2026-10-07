import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:night_reader/core/services/app_file_selection_service.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:provider/provider.dart';

import 'source_manager_provider.dart';
import 'source_editor_page.dart';
import 'source_group_manage_page.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/book_source_part.dart';
import 'package:night_reader/features/search/search_page.dart';
import 'package:night_reader/shared/widgets/app_dialogs.dart';
import 'package:night_reader/shared/widgets/app_state_view.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/glass_menu.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:night_reader/shared/widgets/search_field.dart';
import 'package:night_reader/shared/widgets/swipe_actions.dart';
import 'widgets/import_preview_dialog.dart';
import 'widgets/source_item_tile.dart';
import 'widgets/source_batch_toolbar.dart';
import 'widgets/source_check_status_bar.dart';
import 'widgets/source_manager_menus.dart';
import 'widgets/source_manager_dialogs.dart';

class SourceManagerPage extends StatelessWidget {
  const SourceManagerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SourceManagerProvider(),
      child: const _SourceManagerPageContent(),
    );
  }
}

class _SourceManagerPageContent extends StatefulWidget {
  const _SourceManagerPageContent();

  @override
  State<_SourceManagerPageContent> createState() =>
      _SourceManagerPageContentState();
}

class _SourceManagerPageContentState extends State<_SourceManagerPageContent> {
  final _searchController = TextEditingController();
  bool _isImporting = false;

  /// Telegram 式編輯模式：左側勾選圈、底部批次工具列。有選取時也視為
  /// 編輯模式，避免選取狀態沒有出口。
  bool _editMode = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _isEditing(SourceManagerProvider p) =>
      _editMode || p.selectedUrls.isNotEmpty;

  void _enterEditMode(SourceManagerProvider p, {String? selectUrl}) {
    setState(() => _editMode = true);
    if (selectUrl != null && !p.selectedUrls.contains(selectUrl)) {
      p.toggleSelect(selectUrl);
    }
  }

  void _exitEditMode(SourceManagerProvider p) {
    setState(() => _editMode = false);
    p.clearSelection();
  }

  @override
  Widget build(BuildContext context) {
    final nav = Navigator.of(context);
    return Consumer<SourceManagerProvider>(
      builder: (context, provider, child) {
        final mutationEnabled = !_isImporting && !provider.isMutationBusy;
        final editing = _isEditing(provider) && provider.totalSourceCount > 0;
        return PopScope<void>(
          canPop: !editing,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop || !editing) return;
            _exitEditMode(provider);
          },
          child: Scaffold(
            extendBodyBehindAppBar: true,
            extendBody: true,
            appBar: _buildHeader(
              context,
              nav,
              provider,
              editing: editing,
              mutationEnabled: mutationEnabled,
            ),
            body: Builder(
              builder: (bodyContext) => _buildMainContent(bodyContext, provider),
            ),
            bottomNavigationBar:
                editing
                    ? SelectActionBar(
                      provider: provider,
                      externallyBusy: _isImporting,
                      onEnable:
                          () => _runAction(
                            () => provider.batchSetEnabled(true),
                            errorPrefix: '啟用書源失敗',
                          ),
                      onDisable:
                          () => _runAction(
                            () => provider.batchSetEnabled(false),
                            errorPrefix: '停用書源失敗',
                          ),
                      onAddGroup:
                          () => _showSelectionGroupDialog(
                            context,
                            provider,
                            remove: false,
                          ),
                      onRemoveGroup:
                          () => _showSelectionGroupDialog(
                            context,
                            provider,
                            remove: true,
                          ),
                      onEnableExplore:
                          () => _runAction(
                            () => provider.batchSetEnabledExplore(true),
                            errorPrefix: '啟用發現失敗',
                          ),
                      onDisableExplore:
                          () => _runAction(
                            () => provider.batchSetEnabledExplore(false),
                            errorPrefix: '停用發現失敗',
                          ),
                      onSelectInterval: provider.checkSelectedInterval,
                      onMoveToTop:
                          () => _runAction(
                            provider.moveSelectedToTop,
                            errorPrefix: '移動書源失敗',
                          ),
                      onMoveToBottom:
                          () => _runAction(
                            provider.moveSelectedToBottom,
                            errorPrefix: '移動書源失敗',
                          ),
                      onExport:
                          () => _runAction(() async {
                            final messenger = ScaffoldMessenger.of(context);
                            final copiedToClipboard =
                                await provider.exportSelected();
                            if (!mounted) return;
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  copiedToClipboard
                                      ? '已複製至剪貼簿'
                                      : '書源過多，已改用分享方式匯出',
                                ),
                              ),
                            );
                          }, errorPrefix: '匯出書源失敗'),
                      onShare:
                          () => _runAction(
                            provider.shareSelectedSources,
                            errorPrefix: '分享書源失敗',
                          ),
                      onCheckSource: () {
                        SourceManagerDialogs.showCheckConfigDialog(
                          context,
                          provider,
                        );
                      },
                      onDelete: () {
                        _confirmDeleteSelected(context, provider);
                      },
                    )
                    : null,
          ),
        );
      },
    );
  }

  GlassNavHeader _buildHeader(
    BuildContext context,
    NavigatorState nav,
    SourceManagerProvider provider, {
    required bool editing,
    required bool mutationEnabled,
  }) {
    final showSearch = provider.totalSourceCount > 0;
    final showStatus =
        provider.checkService.isChecking || provider.hasLastCheckReport;
    final bottomChildren = <Widget>[
      if (showSearch)
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppGrouped.margin,
            AppSpacing.xs,
            AppGrouped.margin,
            AppSpacing.xs,
          ),
          child: SearchField(
            controller: _searchController,
            hintText: '搜尋書源名稱、網址',
            glass: true,
            onChanged: provider.setSearchQuery,
          ),
        ),
      if (showStatus)
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppGrouped.margin,
            AppSpacing.xs,
            AppGrouped.margin,
            AppSpacing.xs,
          ),
          child: SourceCheckStatusBar(
            provider: provider,
            onTap: () {
              if (provider.checkService.isChecking) {
                SourceManagerDialogs.showCheckLog(context, provider);
              } else if (provider.lastCheckReport.affectedCount > 0) {
                provider.setFilterGroup(abnormalSourceGroupTag);
              }
            },
          ),
        ),
      if (_isImporting)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: AppGrouped.margin),
          child: ClipRRect(
            borderRadius: AppRadius.pillShape,
            child: LinearProgressIndicator(
              minHeight: 2,
              semanticsLabel: '正在處理書源匯入',
            ),
          ),
        ),
    ];
    final double bottomHeight =
        (showSearch ? SearchField.height + AppSpacing.xs * 2 : 0.0) +
        (showStatus ? SourceCheckStatusBar.height + AppSpacing.xs * 2 : 0.0) +
        (_isImporting ? 2.0 : 0.0);
    final bottom =
        bottomChildren.isEmpty
            ? null
            : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: bottomChildren,
            );

    if (editing) {
      final visibleUrls = provider.sources.map((s) => s.bookSourceUrl);
      final allSelected =
          visibleUrls.isNotEmpty &&
          visibleUrls.every(provider.selectedUrls.contains);
      final busy = provider.isMutationBusy || _isImporting;
      final count = provider.selectedUrls.length;
      return GlassNavHeader(
        title: count == 0 ? '選取書源' : '已選 $count 項',
        leading: GlassTextButton(
          label: allSelected ? '取消全選' : '全選',
          onPressed:
              provider.sources.isNotEmpty && !busy ? provider.selectAll : null,
        ),
        actions: [
          GlassTextButton(
            label: '完成',
            emphasized: true,
            onPressed: () => _exitEditMode(provider),
          ),
        ],
        bottom: bottom,
        bottomHeight: bottomHeight,
      );
    }

    return GlassNavHeader(
      title: '書源管理',
      actions: [
        SourceManagerMenus.buildSortMenu(context, provider),
        SourceManagerMenus.buildGroupMenu(
          context,
          provider,
          onManageGroups: () => _openGroupManagePage(nav, provider),
        ),
        SourceManagerMenus.buildMoreMenu(
          context,
          provider,
          onSelect: () => _enterEditMode(provider),
          onImportUrl: () => _showImportDialog(context, true),
          onImportFile: () => _importFromFile(context),
          onImportClipboard: () => _importFromClipboard(context),
          onManageGroups: () => _openGroupManagePage(nav, provider),
          onNewSource: () => _openNewEditor(provider),
          onCheckAllSources:
              () => SourceManagerDialogs.showCheckConfigDialog(
                context,
                provider,
                checkAll: true,
              ),
          onClearInvalid:
              (p) => SourceManagerDialogs.confirmClearInvalid(context, p),
          onDeleteNonNovel:
              (p) => SourceManagerDialogs.confirmDeleteNonNovel(context, p),
          importEnabled: !_isImporting,
          mutationEnabled: mutationEnabled,
        ),
      ],
      bottom: bottom,
      bottomHeight: bottomHeight,
    );
  }

  Future<void> _openGroupManagePage(
    NavigatorState nav,
    SourceManagerProvider provider,
  ) {
    return nav.push(
      MaterialPageRoute(
        builder:
            (_) => ChangeNotifierProvider<SourceManagerProvider>.value(
              value: provider,
              child: const SourceGroupManagePage(),
            ),
      ),
    );
  }

  Widget _buildMainContent(BuildContext context, SourceManagerProvider p) {
    final padding = MediaQuery.paddingOf(context);
    final chrome = AppChrome.of(context);
    Widget stateView(Widget child) => Padding(
      padding: EdgeInsets.only(top: padding.top, bottom: padding.bottom),
      child: child,
    );

    if (p.isLoading) {
      return stateView(const Center(child: CircularProgressIndicator()));
    }
    if (p.loadErrorMessage != null && p.totalSourceCount == 0) {
      return stateView(
        AppStateView(
          icon: Icons.error_outline,
          title: '書源載入失敗',
          description: p.loadErrorMessage,
          tone: AppStateTone.error,
          primaryAction: AppStateAction(
            label: '重試',
            icon: Icons.refresh,
            onPressed: p.loadSources,
          ),
        ),
      );
    }
    final list = p.sources;
    if (list.isEmpty) {
      if (p.totalSourceCount == 0) {
        return stateView(
          AppStateView(
            icon: Icons.source_outlined,
            title: '尚未加入書源',
            description: '匯入書源後，即可搜尋與探索內容。',
            primaryAction: AppStateAction(
              label: '從網址匯入',
              icon: Icons.link,
              onPressed:
                  _isImporting ? null : () => _showImportDialog(context, true),
            ),
            secondaryAction: AppStateAction(
              label: '從檔案匯入',
              icon: Icons.file_open_outlined,
              onPressed: _isImporting ? null : () => _importFromFile(context),
            ),
          ),
        );
      }
      return stateView(
        AppStateView(
          icon: Icons.search_off,
          title: '找不到符合條件的書源',
          description: '清除搜尋與篩選條件後再試一次。',
          primaryAction: AppStateAction(
            label: '清除搜尋與篩選',
            icon: Icons.clear,
            onPressed: () {
              _searchController.clear();
              p.setSearchQuery('');
              p.setFilterGroup('全部');
            },
          ),
        ),
      );
    }
    final groupByHost = p.groupByDomain;
    final hostLabels =
        groupByHost
            ? list
                .map((source) => p.getSourceHost(source.bookSourceUrl))
                .toList(growable: false)
            : const <String>[];
    bool startsHostGroup(int i) =>
        groupByHost && (i == 0 || hostLabels[i - 1] != hostLabels[i]);

    final canReorder = p.canReorder && !_isImporting;
    final editing = _isEditing(p);

    Widget itemAt(int i) {
      final isLastInGroup = i == list.length - 1 || startsHostGroup(i + 1);
      return _buildItem(
        p,
        list[i],
        index: i,
        editing: editing,
        showHostHeader: !canReorder && startsHostGroup(i),
        hostLabel: groupByHost ? hostLabels[i] : '',
        showSeparator: !isLastInGroup,
      );
    }

    return ColoredBox(
      color: chrome.groupedBackground,
      child: SwipeActionsGroup(
        child: CustomScrollView(
          slivers: [
            SliverPadding(padding: EdgeInsets.only(top: padding.top)),
            if (p.loadErrorMessage != null && p.totalSourceCount > 0)
              SliverToBoxAdapter(
                child: GroupedSection(
                  topGap: AppSpacing.sm,
                  children: [
                    GroupedRow(
                      title: p.loadErrorMessage!,
                      destructive: true,
                      showChevron: false,
                      trailing: Text(
                        '重試',
                        style: AppTextStyles.bodyBase.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      onTap: p.loadSources,
                    ),
                  ],
                ),
              ),
            SliverPadding(
              padding: EdgeInsets.only(
                top: groupByHost ? 0 : AppSpacing.sm,
                bottom: padding.bottom + AppSpacing.xxl,
              ),
              sliver:
                  canReorder
                      ? SliverReorderableList(
                        itemCount: list.length,
                        onReorderItem:
                            (oldIndex, newIndex) => _runAction(
                              () => p.reorderSource(oldIndex, newIndex),
                              errorPrefix: '調整書源排序失敗',
                            ),
                        proxyDecorator:
                            (child, _, _) => DecoratedBox(
                              decoration: BoxDecoration(
                                boxShadow: [
                                  BoxShadow(
                                    color: chrome.glassShadow,
                                    blurRadius: 16,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: child,
                            ),
                        itemBuilder: (ctx, i) => itemAt(i),
                      )
                      : SliverList.builder(
                        itemCount: list.length,
                        itemBuilder: (ctx, i) => itemAt(i),
                      ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItem(
    SourceManagerProvider p,
    BookSourcePart s, {
    required int index,
    required bool editing,
    required bool showHostHeader,
    required String hostLabel,
    required bool showSeparator,
  }) {
    return SourceItemTile(
      key: ValueKey(s.bookSourceUrl),
      source: s,
      provider: p,
      index: index,
      editing: editing,
      showHostHeader: showHostHeader,
      hostLabel: hostLabel,
      showSeparator: showSeparator,
      isSelected: p.selectedUrls.contains(s.bookSourceUrl),
      mutationEnabled: !_isImporting && !p.isMutationBusy,
      onTap: () async {
        if (_isEditing(p)) {
          p.toggleSelect(s.bookSourceUrl);
          return;
        }
        await _openEditor(p, s.bookSourceUrl);
      },
      onLongPress: (rect, preview) => _showSourceMenu(p, s, rect, preview),
      onEdit: () => _openEditor(p, s.bookSourceUrl),
      onMoveToTop:
          () => _runAction(
            () => p.moveToTop(s.bookSourceUrl),
            errorPrefix: '移動書源失敗',
          ),
      onDelete: () => _confirmDeleteSource(p, s),
      onEnabledChanged:
          (_) =>
              _runAction(() => p.toggleEnabled(s), errorPrefix: '更新書源狀態失敗'),
    );
  }

  /// 長按書源：列浮起預覽，旁邊列出單一書源的動作。
  Future<void> _showSourceMenu(
    SourceManagerProvider p,
    BookSourcePart s,
    Rect sourceRect,
    Widget preview,
  ) async {
    final nav = Navigator.of(context);
    final action = await showContextPreviewMenu<String>(
      context: context,
      sourceRect: sourceRect,
      preview: preview,
      previewRadius: AppRadius.cardLg,
      entries: [
        const GlassMenuItem(
          value: 'search',
          label: '在此書源中搜尋',
          icon: Icons.search_rounded,
        ),
        const GlassMenuItem(
          value: 'edit',
          label: '編輯書源',
          icon: Icons.edit_outlined,
        ),
        const GlassMenuItem(
          value: 'debug',
          label: '調試書源',
          icon: Icons.bug_report_outlined,
        ),
        if (s.hasExploreUrl)
          GlassMenuItem(
            value: 'explore',
            label: s.enabledExplore ? '停用發現' : '啟用發現',
            icon:
                s.enabledExplore
                    ? Icons.explore_off_outlined
                    : Icons.travel_explore,
          ),
        const GlassMenuDivider(),
        const GlassMenuItem(
          value: 'top',
          label: '移至最頂',
          icon: Icons.vertical_align_top_rounded,
        ),
        const GlassMenuItem(
          value: 'bottom',
          label: '移至最底',
          icon: Icons.vertical_align_bottom_rounded,
        ),
        const GlassMenuItem(
          value: 'select',
          label: '選取',
          icon: Icons.check_circle_outline_rounded,
        ),
        const GlassMenuDivider(),
        const GlassMenuItem(
          value: 'delete',
          label: '刪除書源',
          icon: Icons.delete_outline_rounded,
          destructive: true,
        ),
      ],
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'search':
        final full = await p.getFullSource(s.bookSourceUrl);
        if (full != null && mounted) {
          nav.push(
            MaterialPageRoute(builder: (_) => SearchPage(initialSource: full)),
          );
        }
      case 'edit':
        await _openEditor(p, s.bookSourceUrl);
      case 'debug':
        final full = await p.getFullSource(s.bookSourceUrl);
        if (full != null && mounted) {
          SourceManagerDialogs.showDebugInput(context, full);
        }
      case 'explore':
        await _runAction(
          () => p.toggleEnabledExplore(s),
          errorPrefix: '更新發現狀態失敗',
        );
      case 'top':
        await _runAction(
          () => p.moveToTop(s.bookSourceUrl),
          errorPrefix: '移動書源失敗',
        );
      case 'bottom':
        await _runAction(
          () => p.moveToBottom(s.bookSourceUrl),
          errorPrefix: '移動書源失敗',
        );
      case 'select':
        _enterEditMode(p, selectUrl: s.bookSourceUrl);
      case 'delete':
        await _confirmDeleteSource(p, s);
    }
  }

  Future<void> _confirmDeleteSource(
    SourceManagerProvider p,
    BookSourcePart s,
  ) async {
    final confirmed = await showAppConfirm(
      context: context,
      title: '刪除書源',
      message: '確定要刪除「${s.bookSourceName}」嗎？',
      confirmLabel: '刪除',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await _runAction(() => p.deleteSource(s), errorPrefix: '刪除書源失敗');
  }

  Future<void> _confirmDeleteSelected(
    BuildContext context,
    SourceManagerProvider p,
  ) async {
    final count = p.selectedUrls.length;
    if (count == 0) return;
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showAppConfirm(
      context: context,
      title: '確認刪除',
      message: '確定要刪除選中的 $count 個書源嗎？',
      confirmLabel: '確定刪除',
      destructive: true,
    );
    if (!confirmed) return;
    try {
      await p.deleteSelected();
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('已刪除 $count 個書源')));
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('刪除書源失敗：$error')));
    }
  }

  Future<void> _showSelectionGroupDialog(
    BuildContext context,
    SourceManagerProvider p, {
    required bool remove,
  }) async {
    final pageContext = context;
    String? inputError;
    await showStatefulAppAlert<void>(
      context: context,
      fieldTexts: const [''],
      builder: (dialogContext, setDialogState, fields) {
        final ctrl = fields.single;
        final chrome = AppChrome.of(dialogContext);
        final scheme = Theme.of(dialogContext).colorScheme;
        return AppAlert<bool>(
          title: remove ? '移出分組' : '加入分組',
          onAction: (confirmed) async {
            if (!confirmed) {
              Navigator.pop(dialogContext);
              return;
            }
            final text = ctrl.text.trim();
            if (text.isEmpty) {
              setDialogState(() => inputError = '請輸入或選擇分組名稱');
              return;
            }
            final selected = p.selectedUrls;
            Navigator.pop(dialogContext);
            try {
              if (remove) {
                await p.selectionRemoveFromGroups(selected, text);
              } else {
                await p.selectionAddToGroups(selected, text);
              }
            } catch (error) {
              if (pageContext.mounted) {
                ScaffoldMessenger.of(pageContext).showSnackBar(
                  SnackBar(
                    content: Text('${remove ? '移出' : '加入'}分組失敗：$error'),
                  ),
                );
              }
            }
          },
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AlertTextField(
                controller: ctrl,
                hintText: '分組名稱',
                errorText: inputError,
                onChanged: (_) {
                  if (inputError != null) {
                    setDialogState(() => inputError = null);
                  }
                },
              ),
              if (p.allGroups.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Container(
                  height: 150,
                  decoration: BoxDecoration(
                    color: chrome.groupedBackground,
                    borderRadius: AppRadius.cardMd,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: p.allGroups.length,
                    separatorBuilder:
                        (_, _) => Padding(
                          padding: const EdgeInsets.only(
                            left: AppSpacing.md,
                          ),
                          child: Container(
                            height: AppGlass.hairline,
                            color: chrome.separator,
                          ),
                        ),
                    itemBuilder: (_, i) {
                      final g = p.allGroups[i];
                      final picked = ctrl.text.trim() == g;
                      return InkWell(
                        onTap: () {
                          ctrl.value = TextEditingValue(
                            text: g,
                            selection: TextSelection.collapsed(
                              offset: g.length,
                            ),
                          );
                          setDialogState(() => inputError = null);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.md,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  g,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.bodyBase.copyWith(
                                    height: 1.3,
                                    color: scheme.onSurface,
                                  ),
                                ),
                              ),
                              if (picked)
                                Icon(
                                  Icons.check_rounded,
                                  size: 18,
                                  color: scheme.primary,
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
          actions: const [
            AppAlertAction(label: '取消', value: false),
            AppAlertAction(label: '確定', value: true, isDefault: true),
          ],
        );
      },
    );
  }

  Future<void> _importWithPreview(BuildContext context, String jsonStr) async {
    final p = context.read<SourceManagerProvider>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final parsed = await p.parseSourcesDetailedAsync(jsonStr);
      if (!context.mounted) return;
      if (parsed.allSources.isEmpty) {
        messenger.showSnackBar(const SnackBar(content: Text('未解析到有效書源')));
        return;
      }
      final preview = await p.previewImport(
        parsed.allSources,
        unsupportedSources: parsed.unsupportedSources,
      );
      if (!context.mounted) return;
      final confirmed = await showImportPreviewDialog(context, preview);
      if (confirmed != null && confirmed.isNotEmpty) {
        final count = await p.importSources(confirmed);
        if (context.mounted) {
          final unsupportedCount =
              confirmed.where((source) => !source.isNovelTextSource).length;
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                unsupportedCount > 0
                    ? '成功匯入 $count 個書源，其中 $unsupportedCount 個已標記為不支援並停用'
                    : '成功匯入 $count 個書源',
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        messenger.showSnackBar(SnackBar(content: Text('匯入失敗: $e')));
      }
    }
  }

  Future<void> _showImportDialog(BuildContext context, bool isUrl) async {
    final pageContext = context;
    String? inputError;
    await showStatefulAppAlert<void>(
      context: context,
      fieldTexts: const [''],
      builder:
          (dialogContext, setDialogState, fields) => AppAlert<bool>(
            title: isUrl ? '網路匯入' : '文本匯入',
            onAction: (confirmed) async {
              if (!confirmed) {
                Navigator.pop(dialogContext);
                return;
              }
              final p = pageContext.read<SourceManagerProvider>();
              final input = fields.single.text.trim();
              if (input.isEmpty) {
                setDialogState(
                  () => inputError = isUrl ? '請輸入匯入網址' : '請貼上書源 JSON',
                );
                return;
              }
              Navigator.pop(dialogContext);
              await _runImportFlow(() async {
                if (isUrl) {
                  final jsonText = await p.fetchImportTextFromUrl(input);
                  if (!pageContext.mounted) return;
                  await _importWithPreview(pageContext, jsonText);
                } else if (pageContext.mounted) {
                  await _importWithPreview(pageContext, input);
                }
              }, errorPrefix: isUrl ? '網路匯入失敗' : '文本匯入失敗');
            },
            content: AlertTextField(
              controller: fields.single,
              hintText: isUrl ? '請輸入 URL' : '請貼上 JSON',
              errorText: inputError,
              maxLines: 5,
              onChanged: (_) {
                if (inputError != null) {
                  setDialogState(() => inputError = null);
                }
              },
            ),
            actions: const [
              AppAlertAction(label: '取消', value: false),
              AppAlertAction(label: '匯入', value: true, isDefault: true),
            ],
          ),
    );
  }

  Future<void> _importFromFile(BuildContext context) async {
    await _runImportFlow(() async {
      final path =
          await AppFileSelectionService.instance.pickBookSourceImportPath();
      if (path == null) return;
      final content = await File(path).readAsString();
      if (context.mounted) await _importWithPreview(context, content);
    }, errorPrefix: '讀取匯入檔案失敗');
  }

  Future<void> _importFromClipboard(BuildContext context) async {
    await _runImportFlow(() async {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text;
      if (!context.mounted) return;
      if (text == null || text.trim().isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('剪貼簿沒有可匯入的內容')));
        return;
      }
      await _importWithPreview(context, text);
    }, errorPrefix: '讀取剪貼簿失敗');
  }

  Future<void> _runImportFlow(
    Future<void> Function() operation, {
    required String errorPrefix,
  }) async {
    if (_isImporting) return;
    setState(() => _isImporting = true);
    try {
      await operation();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$errorPrefix: $error')));
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  Future<void> _openEditor(SourceManagerProvider p, String sourceUrl) async {
    final full = await p.getFullSource(sourceUrl);
    if (full != null && mounted) {
      final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => SourceEditorPage(source: full)),
      );
      if (changed == true && mounted) await p.loadSources();
    }
  }

  Future<void> _openNewEditor(SourceManagerProvider provider) async {
    final changed = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const SourceEditorPage()));
    if (changed == true && mounted) await provider.loadSources();
  }

  Future<void> _runAction(
    Future<void> Function() operation, {
    required String errorPrefix,
  }) async {
    try {
      await operation();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$errorPrefix：$error')));
    }
  }
}
