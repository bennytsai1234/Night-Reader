import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:night_reader/core/services/app_file_selection_service.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:provider/provider.dart';

import 'source_manager_provider.dart';
import 'source_editor_page.dart';
import 'source_group_manage_page.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/book_source_part.dart';
import 'package:night_reader/features/search/search_page.dart';
import 'package:night_reader/shared/widgets/app_bottom_sheet.dart';
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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nav = Navigator.of(context);
    return Consumer<SourceManagerProvider>(
      builder: (context, provider, child) {
        final mutationEnabled = !_isImporting && !provider.isMutationBusy;
        return PopScope<void>(
          canPop: provider.selectedUrls.isEmpty,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop || provider.selectedUrls.isEmpty) return;
            provider.clearSelection();
          },
          child: Scaffold(
            appBar: AppBar(
              title: const Text('書源管理'),
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
                      (p) =>
                          SourceManagerDialogs.confirmClearInvalid(context, p),
                  onDeleteNonNovel:
                      (p) => SourceManagerDialogs.confirmDeleteNonNovel(
                        context,
                        p,
                      ),
                  importEnabled: !_isImporting,
                  mutationEnabled: mutationEnabled,
                ),
              ],
            ),
            body: Column(
              children: [
                if (provider.checkService.isChecking ||
                    provider.hasLastCheckReport)
                  SourceCheckStatusBar(
                    provider: provider,
                    onTap: () {
                      if (provider.checkService.isChecking) {
                        SourceManagerDialogs.showCheckLog(context, provider);
                      } else if (provider.lastCheckReport.affectedCount > 0) {
                        provider.setFilterGroup(abnormalSourceGroupTag);
                      }
                    },
                  ),
                if (_isImporting)
                  const LinearProgressIndicator(semanticsLabel: '正在處理書源匯入'),
                if (provider.loadErrorMessage != null &&
                    provider.totalSourceCount > 0)
                  MaterialBanner(
                    content: Text(provider.loadErrorMessage!),
                    actions: [
                      TextButton(
                        onPressed: provider.loadSources,
                        child: const Text('重試'),
                      ),
                    ],
                  ),
                if (provider.totalSourceCount > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.sm,
                      AppSpacing.md,
                      0,
                    ),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: '搜尋書源名稱、網址',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon:
                            _searchController.text.isNotEmpty
                                ? IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () {
                                    _searchController.clear();
                                    provider.setSearchQuery('');
                                  },
                                )
                                : null,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.sm,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: AppRadius.cardSm,
                        ),
                      ),
                      onChanged: provider.setSearchQuery,
                    ),
                  ),
                Expanded(child: _buildMainContent(provider)),
              ],
            ),
            bottomNavigationBar:
                provider.totalSourceCount > 0
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

  Widget _buildMainContent(SourceManagerProvider p) {
    if (p.isLoading) return const Center(child: CircularProgressIndicator());
    if (p.loadErrorMessage != null && p.totalSourceCount == 0) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(p.loadErrorMessage!),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton(onPressed: p.loadSources, child: const Text('重試')),
          ],
        ),
      );
    }
    final list = p.sources;
    if (list.isEmpty) {
      if (p.totalSourceCount == 0) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.source_outlined,
                  size: 52,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: AppSpacing.md),
                Text('尚未加入書源', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '匯入書源後，即可搜尋與探索內容。',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.lg),
                FilledButton.icon(
                  onPressed:
                      _isImporting
                          ? null
                          : () => _showImportDialog(context, true),
                  icon: const Icon(Icons.link),
                  label: const Text('從網址匯入'),
                ),
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton.icon(
                  onPressed:
                      _isImporting ? null : () => _importFromFile(context),
                  icon: const Icon(Icons.file_open_outlined),
                  label: const Text('從檔案匯入'),
                ),
              ],
            ),
          ),
        );
      }
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('找不到符合條件的書源'),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: () {
                _searchController.clear();
                p.setSearchQuery('');
                p.setFilterGroup('全部');
              },
              child: const Text('清除搜尋與篩選'),
            ),
          ],
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

    final canReorder = p.canReorder && !_isImporting;

    if (canReorder) {
      return ReorderableListView.builder(
        itemCount: list.length,
        onReorderItem:
            (oldIndex, newIndex) => _runAction(
              () => p.reorderSource(oldIndex, newIndex),
              errorPrefix: '調整書源排序失敗',
            ),
        itemBuilder:
            (ctx, i) => _buildItem(
              p,
              list[i],
              index: i,
              showHostHeader: false,
              hostLabel: '',
            ),
      );
    } else {
      return ListView.separated(
        itemCount: list.length,
        separatorBuilder: (ctx, i) => const Divider(height: 1),
        itemBuilder: (ctx, i) {
          final showHostHeader =
              groupByHost && (i == 0 || hostLabels[i - 1] != hostLabels[i]);
          return _buildItem(
            p,
            list[i],
            index: i,
            showHostHeader: showHostHeader,
            hostLabel: groupByHost ? hostLabels[i] : '',
          );
        },
      );
    }
  }

  Widget _buildItem(
    SourceManagerProvider p,
    BookSourcePart s, {
    int? index,
    required bool showHostHeader,
    required String hostLabel,
  }) {
    return SourceItemTile(
      key: ValueKey(s.bookSourceUrl),
      source: s,
      provider: p,
      index: index,
      showHostHeader: showHostHeader,
      hostLabel: hostLabel,
      isSelected: p.selectedUrls.contains(s.bookSourceUrl),
      mutationEnabled: !_isImporting && !p.isMutationBusy,
      onTap: () async {
        if (p.selectedUrls.isNotEmpty) {
          p.toggleSelect(s.bookSourceUrl);
          return;
        }
        await _openEditor(p, s.bookSourceUrl);
      },
      onLongPress: () {
        p.toggleSelect(s.bookSourceUrl);
      },
      onEdit: () async {
        await _openEditor(p, s.bookSourceUrl);
      },
      onShowMenu: () {
        _showSourceMenu(context, p, s);
      },
      onEnabledChanged:
          (v) => _runAction(() => p.toggleEnabled(s), errorPrefix: '更新書源狀態失敗'),
    );
  }

  void _showSourceMenu(
    BuildContext context,
    SourceManagerProvider p,
    BookSourcePart s,
  ) {
    final nav = Navigator.of(context);
    AppBottomSheet.show(
      context: context,
      title: s.bookSourceName,
      icon: Icons.source_rounded,
      children: [
        ListTile(
          shape: RoundedRectangleBorder(borderRadius: AppRadius.cardMd),
          leading: const Icon(Icons.search),
          title: const Text('在此書源中搜尋', style: AppTextStyles.bodySm),
          onTap: () async {
            Navigator.pop(context);
            final full = await p.getFullSource(s.bookSourceUrl);
            if (full != null && context.mounted) {
              nav.push(
                MaterialPageRoute(
                  builder: (_) => SearchPage(initialSource: full),
                ),
              );
            }
          },
        ),
        ListTile(
          shape: RoundedRectangleBorder(borderRadius: AppRadius.cardMd),
          leading: const Icon(Icons.edit_outlined),
          title: const Text('編輯書源', style: AppTextStyles.bodySm),
          onTap: () async {
            Navigator.pop(context);
            await _openEditor(p, s.bookSourceUrl);
          },
        ),
        ListTile(
          shape: RoundedRectangleBorder(borderRadius: AppRadius.cardMd),
          leading: const Icon(Icons.bug_report_outlined),
          title: const Text('調試書源', style: AppTextStyles.bodySm),
          onTap: () async {
            Navigator.pop(context);
            final full = await p.getFullSource(s.bookSourceUrl);
            if (full != null && context.mounted) {
              SourceManagerDialogs.showDebugInput(context, full);
            }
          },
        ),
        if (s.hasExploreUrl)
          ListTile(
            shape: RoundedRectangleBorder(borderRadius: AppRadius.cardMd),
            leading: Icon(
              s.enabledExplore
                  ? Icons.explore_off_outlined
                  : Icons.travel_explore,
            ),
            title: Text(
              s.enabledExplore ? '停用發現' : '啟用發現',
              style: AppTextStyles.bodySm,
            ),
            onTap: () async {
              Navigator.pop(context);
              await _runAction(
                () => p.toggleEnabledExplore(s),
                errorPrefix: '更新發現狀態失敗',
              );
            },
          ),
        const Divider(indent: 16, endIndent: 16),
        ListTile(
          shape: RoundedRectangleBorder(borderRadius: AppRadius.cardMd),
          leading: const Icon(Icons.vertical_align_top_rounded),
          title: const Text('移至最頂', style: AppTextStyles.bodySm),
          onTap: () async {
            Navigator.pop(context);
            await _runAction(
              () => p.moveToTop(s.bookSourceUrl),
              errorPrefix: '移動書源失敗',
            );
          },
        ),
        ListTile(
          shape: RoundedRectangleBorder(borderRadius: AppRadius.cardMd),
          leading: const Icon(Icons.vertical_align_bottom_rounded),
          title: const Text('移至最底', style: AppTextStyles.bodySm),
          onTap: () async {
            Navigator.pop(context);
            await _runAction(
              () => p.moveToBottom(s.bookSourceUrl),
              errorPrefix: '移動書源失敗',
            );
          },
        ),
        const Divider(indent: 16, endIndent: 16),
        ListTile(
          shape: RoundedRectangleBorder(borderRadius: AppRadius.cardMd),
          leading: Icon(
            Icons.delete_sweep_outlined,
            color: Theme.of(context).colorScheme.error,
          ),
          title: Text(
            '刪除書源',
            style: AppTextStyles.bodySm.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
          onTap: () async {
            Navigator.pop(context);
            await _runAction(() => p.deleteSource(s), errorPrefix: '刪除書源失敗');
          },
        ),
      ],
    );
  }

  void _confirmDeleteSelected(BuildContext context, SourceManagerProvider p) {
    final count = p.selectedUrls.length;
    if (count == 0) return;
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('確認刪除'),
            content: Text('確定要刪除選中的 $count 個書源嗎？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    await p.deleteSelected();
                    if (!mounted) return;
                    messenger.showSnackBar(
                      SnackBar(content: Text('已刪除 $count 個書源')),
                    );
                  } catch (error) {
                    if (!mounted) return;
                    messenger.showSnackBar(
                      SnackBar(content: Text('刪除書源失敗：$error')),
                    );
                  }
                },
                child: Text(
                  '確定刪除',
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                ),
              ),
            ],
          ),
    );
  }

  Future<void> _showSelectionGroupDialog(
    BuildContext context,
    SourceManagerProvider p, {
    required bool remove,
  }) async {
    final ctrl = TextEditingController();
    final pageContext = context;
    String? inputError;
    try {
      await showDialog<void>(
        context: context,
        builder:
            (ctx) => StatefulBuilder(
              builder:
                  (context, setDialogState) => AlertDialog(
                    title: Text(remove ? '移出分組' : '加入分組'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: ctrl,
                          decoration: InputDecoration(
                            hintText: '分組名稱',
                            errorText: inputError,
                          ),
                          onChanged: (_) {
                            if (inputError != null) {
                              setDialogState(() => inputError = null);
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 150,
                          width: double.maxFinite,
                          child: ListView.builder(
                            itemCount: p.allGroups.length,
                            itemBuilder: (ctx2, i) {
                              final g = p.allGroups[i];
                              return ListTile(
                                title: Text(g),
                                dense: true,
                                onTap: () {
                                  ctrl.value = TextEditingValue(
                                    text: g,
                                    selection: TextSelection.collapsed(
                                      offset: g.length,
                                    ),
                                  );
                                  setDialogState(() => inputError = null);
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('取消'),
                      ),
                      ElevatedButton(
                        onPressed: () async {
                          final text = ctrl.text.trim();
                          if (text.isEmpty) {
                            setDialogState(() => inputError = '請輸入或選擇分組名稱');
                            return;
                          }
                          final selected = p.selectedUrls;
                          Navigator.pop(ctx);
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
                                  content: Text(
                                    '${remove ? '移出' : '加入'}分組失敗：$error',
                                  ),
                                ),
                              );
                            }
                          }
                        },
                        child: const Text('確定'),
                      ),
                    ],
                  ),
            ),
      );
    } finally {
      ctrl.dispose();
    }
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
    final ctrl = TextEditingController();
    String? inputError;
    try {
      await showDialog<void>(
        context: context,
        builder:
            (ctx) => StatefulBuilder(
              builder:
                  (context, setDialogState) => AlertDialog(
                    title: Text(isUrl ? '網路匯入' : '文本匯入'),
                    content: TextField(
                      controller: ctrl,
                      decoration: InputDecoration(
                        hintText: isUrl ? '請輸入 URL' : '請貼上 JSON',
                        errorText: inputError,
                      ),
                      maxLines: 5,
                      onChanged: (_) {
                        if (inputError != null) {
                          setDialogState(() => inputError = null);
                        }
                      },
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('取消'),
                      ),
                      ElevatedButton(
                        onPressed: () async {
                          final p = pageContext.read<SourceManagerProvider>();
                          final input = ctrl.text.trim();
                          if (input.isEmpty) {
                            setDialogState(
                              () =>
                                  inputError = isUrl ? '請輸入匯入網址' : '請貼上書源 JSON',
                            );
                            return;
                          }
                          Navigator.pop(ctx);
                          await _runImportFlow(() async {
                            if (isUrl) {
                              final jsonText = await p.fetchImportTextFromUrl(
                                input,
                              );
                              if (!pageContext.mounted) return;
                              await _importWithPreview(pageContext, jsonText);
                            } else if (pageContext.mounted) {
                              await _importWithPreview(pageContext, input);
                            }
                          }, errorPrefix: isUrl ? '網路匯入失敗' : '文本匯入失敗');
                        },
                        child: const Text('匯入'),
                      ),
                    ],
                  ),
            ),
      );
    } finally {
      ctrl.dispose();
    }
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
