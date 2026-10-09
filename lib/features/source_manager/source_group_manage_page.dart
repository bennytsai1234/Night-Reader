import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/context_ext.dart';
import 'package:night_reader/shared/widgets/app_dialogs.dart';
import 'package:night_reader/shared/widgets/app_state_view.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/glass_menu.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:night_reader/shared/widgets/swipe_actions.dart';

import 'source_manager_provider.dart';

class SourceGroupManagePage extends StatelessWidget {
  const SourceGroupManagePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassNavHeader(
        title: '書源分組管理',
        actions: [
          Consumer<SourceManagerProvider>(
            builder: (context, provider, _) => GlassIconButton(
              icon: Icons.add_rounded,
              tooltip: '新增分組',
              onPressed: provider.isMutationBusy
                  ? null
                  : () => _showEditDialog(context),
            ),
          ),
        ],
      ),
      body: Consumer<SourceManagerProvider>(
        builder: (context, provider, child) {
          final groups = provider.allGroups;
          final mutationEnabled = !provider.isMutationBusy;

          if (groups.isEmpty) {
            return Padding(
              padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
              child: AppStateView(
                icon: Icons.folder_outlined,
                title: '尚未建立自訂分組',
                description: '建立分組後，可依分組管理、篩選與分享書源。',
                primaryAction: AppStateAction(
                  label: '新增分組',
                  icon: Icons.add,
                  onPressed: mutationEnabled
                      ? () => _showEditDialog(context)
                      : null,
                ),
              ),
            );
          }

          return SwipeActionsGroup(
            child: GroupedListView(
              children: [
                GroupedSection(
                  topGap: AppSpacing.sm,
                  children: [
                    for (final group in groups)
                      SwipeActions(
                        key: ValueKey(group),
                        enabled: mutationEnabled,
                        leading: [
                          SwipeAction(
                            label: '分享',
                            icon: Icons.share_outlined,
                            color: AppTint.azurite.color,
                            onPressed: () =>
                                _shareGroup(context, provider, group),
                          ),
                        ],
                        trailing: [
                          SwipeAction(
                            label: '重新命名',
                            icon: Icons.edit_outlined,
                            color: AppTint.tea.color,
                            onPressed: () =>
                                _showEditDialog(context, oldName: group),
                          ),
                          SwipeAction(
                            label: '刪除',
                            icon: Icons.delete_outline_rounded,
                            color: context.danger,
                            destructive: true,
                            onPressed: () =>
                                _confirmDelete(context, provider, group),
                          ),
                        ],
                        child: _GroupRow(
                          group: group,
                          enabled: mutationEnabled,
                          onMenu: (rowContext) =>
                              _showGroupMenu(rowContext, provider, group),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _showGroupMenu(
    BuildContext rowContext,
    SourceManagerProvider provider,
    String group,
  ) async {
    final action = await showGlassMenu<String>(
      context: rowContext,
      anchor: globalRectOf(rowContext),
      entries: const [
        GlassMenuItem(
          value: 'share',
          label: '分享此分組書源',
          icon: Icons.share_outlined,
        ),
        GlassMenuItem(
          value: 'rename',
          label: '重新命名分組',
          icon: Icons.edit_outlined,
        ),
        GlassMenuDivider(),
        GlassMenuItem(
          value: 'delete',
          label: '刪除分組',
          icon: Icons.delete_outline_rounded,
          destructive: true,
        ),
      ],
    );
    if (action == null || !rowContext.mounted) return;
    switch (action) {
      case 'share':
        _shareGroup(rowContext, provider, group);
      case 'rename':
        await _showEditDialog(rowContext, oldName: group);
      case 'delete':
        await _confirmDelete(rowContext, provider, group);
    }
  }

  void _shareGroup(
    BuildContext context,
    SourceManagerProvider p,
    String groupName,
  ) async {
    final urls = p.sourceUrlsInGroup(groupName);

    if (urls.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('該分組下無書源')));
      return;
    }

    try {
      await p.shareSourcesByUrls(urls, fileName: '$groupName.legado');
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('分享分組失敗：$error')));
      }
    }
  }

  Future<void> _showEditDialog(BuildContext context, {String? oldName}) async {
    final provider = context.read<SourceManagerProvider>();
    final pageContext = context;
    String? inputError;
    await showStatefulAppAlert<void>(
      context: context,
      fieldTexts: [oldName ?? ''],
      builder: (dialogContext, setDialogState, fields) => AppAlert<bool>(
        title: oldName == null ? '新增分組' : '重新命名分組',
        onAction: (confirmed) async {
          if (!confirmed) {
            Navigator.pop(dialogContext);
            return;
          }
          final name = fields.single.text.trim();
          if (name.isEmpty) {
            setDialogState(() => inputError = '請輸入分組名稱');
            return;
          }
          Navigator.pop(dialogContext);
          try {
            if (oldName == null) {
              await provider.addGroup(name);
            } else {
              await provider.renameGroup(oldName, name);
            }
          } catch (error) {
            if (pageContext.mounted) {
              ScaffoldMessenger.of(pageContext)
                  .showSnackBar(SnackBar(content: Text('儲存分組失敗：$error')));
            }
          }
        },
        content: AlertTextField(
          controller: fields.single,
          autofocus: true,
          hintText: '輸入分組名稱',
          errorText: inputError,
          onChanged: (_) {
            if (inputError != null) {
              setDialogState(() => inputError = null);
            }
          },
        ),
        actions: const [
          AppAlertAction(label: '取消', value: false),
          AppAlertAction(label: '確定', value: true, isDefault: true),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    SourceManagerProvider provider,
    String name,
  ) async {
    final confirmed = await showAppConfirm(
      context: context,
      title: '刪除分組',
      message: '確定要刪除分組 "$name" 嗎？\n這不會刪除書源，只會移除該分組標籤。',
      confirmLabel: '刪除',
      destructive: true,
    );
    if (!confirmed) return;
    try {
      await provider.deleteGroup(name);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('刪除分組失敗：$error')));
      }
    }
  }
}

/// 分組列：不透明底讓滑動動作藏在列下方；選單錨點取列本身的範圍。
class _GroupRow extends StatelessWidget implements GroupedRowLike {
  const _GroupRow({
    required this.group,
    required this.enabled,
    required this.onMenu,
  });

  final String group;
  final bool enabled;
  final ValueChanged<BuildContext> onMenu;

  @override
  bool get hasLeading => true;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppChrome.of(context).groupedSurface,
      child: GroupedRow(
        title: group,
        leading: const GroupedIconTile(
          Icons.folder_rounded,
          tint: AppTint.gold,
        ),
        enabled: enabled,
        showChevron: false,
        onTap: () => onMenu(context),
        onLongPress: () => onMenu(context),
      ),
    );
  }
}
