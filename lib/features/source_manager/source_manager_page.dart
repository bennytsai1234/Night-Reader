import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reader/shared/theme/app_tokens.dart';
import 'package:reader/shared/theme/app_text_styles.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'source_manager_provider.dart';
import 'source_editor_page.dart';
import 'source_group_manage_page.dart';
import 'package:reader/core/models/book_source.dart';
import 'package:reader/core/models/book_source_part.dart';
import 'package:reader/features/search/search_page.dart';
import 'package:reader/shared/widgets/app_bottom_sheet.dart';
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
                  onNewSource:
                      () => nav.push(
                        MaterialPageRoute(
                          builder: (_) => const SourceEditorPage(),
                        ),
                      ),
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
            // 始終顯示 SelectActionBar (對標 legado)
            bottomNavigationBar: SelectActionBar(
              provider: provider,
              onEnable: () => provider.batchSetEnabled(true),
              onDisable: () => provider.batchSetEnabled(false),
              onAddGroup: () => _showAddGroupDialog(context, provider),
              onRemoveGroup: () => _showRemoveGroupDialog(context, provider),
              onEnableExplore: () => provider.batchSetEnabledExplore(true),
              onDisableExplore: () => provider.batchSetEnabledExplore(false),
              onSelectInterval: provider.checkSelectedInterval,
              onMoveToTop: () => provider.moveSelectedToTop(),
              onMoveToBottom: () => provider.moveSelectedToBottom(),
              onExport: () async {
                final messenger = ScaffoldMessenger.of(context);
                final copiedToClipboard = await provider.exportSelected();
                if (!mounted) return;
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      copiedToClipboard ? '已複製至剪貼簿' : '書源過多，已改用分享方式匯出',
                    ),
                  ),
                );
              },
              onShare: () => provider.shareSelectedSources(),
              onCheckSource: () {
                SourceManagerDialogs.showCheckConfigDialog(context, provider);
              },
              onDelete: () {
                _confirmDeleteSelected(context, provider);
              },
            ),
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
    final list = p.sources;
    if (list.isEmpty) return const Center(child: Text('暫無書源'));
    final groupByHost = p.groupByDomain;
    final hostLabels =
        groupByHost
            ? list
                .map((source) => p.getSourceHost(source.bookSourceUrl))
                .toList(growable: false)
            : const <String>[];

    // 只有在手動排序 (0) 模式下才允許拖拽
    final bool canReorder = p.sortMode == 0 && !groupByHost;

    if (canReorder) {
      return ReorderableListView.builder(
        itemCount: list.length,
        onReorderItem:
            (oldIndex, newIndex) => p.reorderSource(oldIndex, newIndex),
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
      onEnabledChanged: (v) => p.toggleEnabled(s),
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
              await p.toggleEnabledExplore(s);
            },
          ),
        const Divider(indent: 16, endIndent: 16),
        ListTile(
          shape: RoundedRectangleBorder(borderRadius: AppRadius.cardMd),
          leading: const Icon(Icons.vertical_align_top_rounded),
          title: const Text('移至最頂', style: AppTextStyles.bodySm),
          onTap: () async {
            Navigator.pop(context);
            await p.moveToTop(s.bookSourceUrl);
          },
        ),
        ListTile(
          shape: RoundedRectangleBorder(borderRadius: AppRadius.cardMd),
          leading: const Icon(Icons.vertical_align_bottom_rounded),
          title: const Text('移至最底', style: AppTextStyles.bodySm),
          onTap: () async {
            Navigator.pop(context);
            await p.moveToBottom(s.bookSourceUrl);
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
          onTap: () {
            Navigator.pop(context);
            p.deleteSource(s);
          },
        ),
      ],
    );
  }

  /// 確認刪除選中書源 (對標 legado onClickSelectBarMainAction)
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
                  await p.deleteSelected();
                  if (!mounted) return;
                  messenger.showSnackBar(
                    SnackBar(content: Text('已刪除 $count 個書源')),
                  );
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

  /// 加入分組 (對標 legado selectionAddToGroups)
  void _showAddGroupDialog(BuildContext context, SourceManagerProvider p) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('加入分組'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: ctrl,
                  decoration: const InputDecoration(hintText: '分組名稱'),
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
                        onTap: () => ctrl.text = g,
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
                onPressed: () {
                  final text = ctrl.text.trim();
                  if (text.isNotEmpty) {
                    p.selectionAddToGroups(p.selectedUrls, text);
                  }
                  Navigator.pop(ctx);
                },
                child: const Text('確定'),
              ),
            ],
          ),
    );
  }

  /// 移出分組 (對標 legado selectionRemoveFromGroups)
  void _showRemoveGroupDialog(BuildContext context, SourceManagerProvider p) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('移出分組'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: ctrl,
                  decoration: const InputDecoration(hintText: '分組名稱'),
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
                        onTap: () => ctrl.text = g,
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
                onPressed: () {
                  final text = ctrl.text.trim();
                  if (text.isNotEmpty) {
                    p.selectionRemoveFromGroups(p.selectedUrls, text);
                  }
                  Navigator.pop(ctx);
                },
                child: const Text('確定'),
              ),
            ],
          ),
    );
  }

  Future<void> _importWithPreview(BuildContext context, String jsonStr) async {
    final p = context.read<SourceManagerProvider>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final parsed = await p.parseSourcesDetailedAsync(jsonStr);
      if (parsed.allSources.isEmpty) {
        if (parsed.unsupportedSources.isNotEmpty) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                '解析到 ${parsed.unsupportedSources.length} 個不支援來源，但沒有可匯入書源',
              ),
            ),
          );
        } else {
          messenger.showSnackBar(const SnackBar(content: Text('未解析到有效書源')));
        }
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
          final unsupportedCount = parsed.unsupportedSources.length;
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
      messenger.showSnackBar(SnackBar(content: Text('匯入失敗: $e')));
    }
  }

  void _showImportDialog(BuildContext context, bool isUrl) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(isUrl ? '網路匯入' : '文本匯入'),
            content: TextField(
              controller: ctrl,
              decoration: InputDecoration(
                hintText: isUrl ? '請輸入 URL' : '請貼上 JSON',
              ),
              maxLines: 5,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final p = context.read<SourceManagerProvider>();
                  final input = ctrl.text.trim();
                  if (input.isEmpty) {
                    Navigator.pop(ctx);
                    return;
                  }
                  Navigator.pop(ctx);
                  if (isUrl) {
                    try {
                      final jsonText = await p.fetchImportTextFromUrl(input);
                      if (!context.mounted) return;
                      await _importWithPreview(context, jsonText);
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text('網路匯入失敗: $e')));
                    }
                  } else {
                    if (!context.mounted) return;
                    await _importWithPreview(context, input);
                  }
                },
                child: const Text('匯入'),
              ),
            ],
          ),
    );
  }

  Future<void> _importFromFile(BuildContext context) async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json', 'txt', 'legado'],
      );
      if (res?.files.single.path != null && context.mounted) {
        final content = await File(res!.files.single.path!).readAsString();
        if (context.mounted) await _importWithPreview(context, content);
      }
    } catch (_) {}
  }

  Future<void> _importFromClipboard(BuildContext context) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && context.mounted) {
      await _importWithPreview(context, data!.text!);
    }
  }

  Future<void> _openEditor(SourceManagerProvider p, String sourceUrl) async {
    final nav = Navigator.of(context);
    final full = await p.getFullSource(sourceUrl);
    if (full != null && mounted) {
      nav.push(
        MaterialPageRoute(builder: (_) => SourceEditorPage(source: full)),
      );
    }
  }
}
