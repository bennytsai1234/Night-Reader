import 'package:flutter/material.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import '../source_manager_provider.dart';

/// 底部選取操作列 — 對標 legado SelectActionBar
/// 始終顯示於書源管理頁底部，提供全選/反選/刪除及溢出選單。
class SelectActionBar extends StatelessWidget {
  final SourceManagerProvider provider;

  // 溢出選單回呼
  final VoidCallback onEnable;
  final VoidCallback onDisable;
  final VoidCallback onAddGroup;
  final VoidCallback onRemoveGroup;
  final VoidCallback onEnableExplore;
  final VoidCallback onDisableExplore;
  final VoidCallback onSelectInterval;
  final VoidCallback onMoveToTop;
  final VoidCallback onMoveToBottom;
  final VoidCallback onExport;
  final VoidCallback onShare;
  final VoidCallback onCheckSource;
  final VoidCallback onDelete;
  final bool externallyBusy;

  const SelectActionBar({
    super.key,
    required this.provider,
    required this.onEnable,
    required this.onDisable,
    required this.onAddGroup,
    required this.onRemoveGroup,
    required this.onEnableExplore,
    required this.onDisableExplore,
    required this.onSelectInterval,
    required this.onMoveToTop,
    required this.onMoveToBottom,
    required this.onExport,
    required this.onShare,
    required this.onCheckSource,
    required this.onDelete,
    this.externallyBusy = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectCount = provider.selectedUrls.length;
    final allCount = provider.sources.length;
    final visibleSelectedCount =
        provider.sources
            .where(
              (source) => provider.selectedUrls.contains(source.bookSourceUrl),
            )
            .length;
    final hiddenSelectedCount = selectCount - visibleSelectedCount;
    final hasSelection = selectCount > 0;
    final isBusy = provider.isMutationBusy || externallyBusy;
    final actionsEnabled = hasSelection && !isBusy;
    final allSelected = visibleSelectedCount == allCount && allCount > 0;
    final selectionLabel =
        allCount == 0 && hasSelection
            ? '已選 $selectCount 個（目前篩選無項目）'
            : '${allSelected ? '取消全選' : '全選'} '
                '($visibleSelectedCount/$allCount)'
                '${hiddenSelectedCount > 0 ? '，另選 $hiddenSelectedCount 個' : ''}';

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: allCount > 0 && !isBusy ? provider.selectAll : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            allSelected
                                ? Icons.check_box
                                : Icons.check_box_outline_blank,
                            size: 22,
                            color:
                                allSelected ? theme.colorScheme.primary : null,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              selectionLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.bodyXs.copyWith(
                                color: theme.textTheme.bodyMedium?.color,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // 反選
                TextButton(
                  onPressed:
                      allCount > 0 && !isBusy
                          ? () => provider.revertSelection()
                          : null,
                  child: const Text('反選', style: AppTextStyles.bodyXs),
                ),
              ],
            ),
          ),

          // 刪除 (主操作)
          TextButton(
            onPressed: actionsEnabled ? onDelete : null,
            child: Text(
              '刪除',
              style: AppTextStyles.bodyXs.copyWith(
                color:
                    actionsEnabled
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),

          // 溢出選單
          PopupMenuButton<String>(
            icon: Icon(
              Icons.more_vert,
              color: actionsEnabled ? null : theme.colorScheme.onSurfaceVariant,
            ),
            tooltip: isBusy ? '操作進行中' : '更多批次操作',
            enabled: actionsEnabled,
            onSelected: _onMenuSelected,
            itemBuilder:
                (context) => [
                  _menuItem('enable', Icons.toggle_on_outlined, '啟用選中'),
                  _menuItem('disable', Icons.toggle_off_outlined, '禁用選中'),
                  const PopupMenuDivider(),
                  _menuItem('add_group', Icons.playlist_add, '加入分組'),
                  _menuItem('remove_group', Icons.playlist_remove, '移出分組'),
                  _menuItem('enable_explore', Icons.travel_explore, '啟用發現'),
                  _menuItem(
                    'disable_explore',
                    Icons.explore_off_outlined,
                    '禁用發現',
                  ),
                  const PopupMenuDivider(),
                  _menuItem('select_interval', Icons.select_all, '連續選取'),
                  _menuItem('top', Icons.vertical_align_top, '置頂'),
                  _menuItem('bottom', Icons.vertical_align_bottom, '置底'),
                  const PopupMenuDivider(),
                  _menuItem('export', Icons.file_download_outlined, '匯出選中'),
                  _menuItem('share', Icons.share_outlined, '分享選中'),
                  const PopupMenuDivider(),
                  _menuItem('check', Icons.playlist_add_check, '校驗選中'),
                ],
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String text) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [Icon(icon, size: 20), const SizedBox(width: 12), Text(text)],
      ),
    );
  }

  void _onMenuSelected(String value) {
    switch (value) {
      case 'enable':
        onEnable();
        break;
      case 'disable':
        onDisable();
        break;
      case 'add_group':
        onAddGroup();
        break;
      case 'remove_group':
        onRemoveGroup();
        break;
      case 'enable_explore':
        onEnableExplore();
        break;
      case 'disable_explore':
        onDisableExplore();
        break;
      case 'select_interval':
        onSelectInterval();
        break;
      case 'top':
        onMoveToTop();
        break;
      case 'bottom':
        onMoveToBottom();
        break;
      case 'export':
        onExport();
        break;
      case 'share':
        onShare();
        break;
      case 'check':
        onCheckSource();
        break;
    }
  }
}
