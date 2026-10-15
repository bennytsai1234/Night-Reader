import 'package:flutter/material.dart';
import 'package:night_reader/shared/widgets/glass_menu.dart';

import '../source_manager_provider.dart';

/// 書源管理頁首的「更多」選單：頁首只放這一顆，標題才不會被擠到；
/// 分組篩選與排序在第一層各有一項，點了在同一處開出第二層。
class SourceManagerMenus {
  static const List<String> _statusFilters = [
    '全部',
    '已啟用',
    '已禁用',
    '已啟用發現',
    '已禁用發現',
    '無分組',
  ];

  /// 分組與篩選的選單項目；選回值是篩選名稱或 `manage_groups`。
  static List<GlassMenuEntry<String>> _filterEntries(
    SourceManagerProvider provider,
  ) => [
    for (final filter in _statusFilters)
      GlassMenuItem(
        value: filter,
        label: filter,
        checked: provider.filterGroup == filter,
      ),
    if (provider.allGroups.isNotEmpty) const GlassMenuDivider(),
    for (final group in provider.allGroups)
      GlassMenuItem(
        value: group,
        label: group,
        checked: provider.filterGroup == group,
      ),
    const GlassMenuDivider(),
    const GlassMenuItem(
      value: 'manage_groups',
      icon: Icons.edit_note_outlined,
      label: '管理分組',
    ),
  ];

  static const List<String> _sortModes = [
    '手動排序',
    '自動排序',
    '按名稱',
    '按網址',
    '按更新時間',
  ];

  /// 排序方式的選單項目；選回值是 `desc` 或排序序號。
  static List<GlassMenuEntry<String>> _sortEntries(
    SourceManagerProvider provider,
  ) => [
    GlassMenuItem(
      value: 'desc',
      label: '倒序排列',
      icon: Icons.swap_vert_rounded,
      checked: provider.sortDesc,
    ),
    const GlassMenuDivider(),
    for (var i = 0; i < _sortModes.length; i++)
      GlassMenuItem(
        value: '$i',
        label: _sortModes[i],
        checked: provider.sortMode == i,
      ),
  ];

  /// 在「更多」鈕的位置接著開出第二層選單（分組與篩選、排序方式）。
  static Future<void> _openSubmenu(
    BuildContext buttonContext,
    List<GlassMenuEntry<String>> entries,
    ValueChanged<String> onSelected,
  ) async {
    final value = await showGlassMenu<String>(
      context: buttonContext,
      anchor: globalRectOf(buttonContext),
      entries: entries,
    );
    if (value != null) onSelected(value);
  }

  static Widget buildMoreMenu(
    BuildContext context,
    SourceManagerProvider provider, {
    required VoidCallback onSelect,
    required VoidCallback onImportUrl,
    required VoidCallback onImportFile,
    required VoidCallback onImportClipboard,
    required VoidCallback onManageGroups,
    required VoidCallback onNewSource,
    required VoidCallback onCheckAllSources,
    required VoidCallback onClearCheckMarks,
    required Function(SourceManagerProvider) onClearInvalid,
    required Function(SourceManagerProvider) onDeleteNonNovel,
    bool importEnabled = true,
    bool mutationEnabled = true,
  }) {
    return Builder(
      builder: (buttonContext) => GlassMenuButton<String>(
        tooltip: '更多操作',
        onSelected: (value) {
          switch (value) {
            case 'filter':
              _openSubmenu(buttonContext, _filterEntries(provider), (value) {
                if (value == 'manage_groups') {
                  onManageGroups();
                } else {
                  provider.setFilterGroup(value);
                }
              });
            case 'sort':
              _openSubmenu(buttonContext, _sortEntries(provider), (value) {
                if (value == 'desc') {
                  provider.toggleSortDesc();
                } else {
                  provider.setSortMode(int.parse(value));
                }
              });
            case 'select':
              onSelect();
            case 'import_url':
              onImportUrl();
            case 'import_file':
              onImportFile();
            case 'import_clipboard':
              onImportClipboard();
            case 'new_source':
              onNewSource();
            case 'manage_groups':
              onManageGroups();
            case 'check_all':
              onCheckAllSources();
            case 'clear_check_marks':
              onClearCheckMarks();
            case 'group_domain':
              provider.toggleGroupByDomain();
            case 'clear_invalid':
              onClearInvalid(provider);
            case 'clean_non_novel':
              onDeleteNonNovel(provider);
          }
        },
        entriesBuilder: (_) => [
          GlassMenuItem(
            value: 'filter',
            icon: Icons.folder_outlined,
            label: '分組與篩選',
          ),
          GlassMenuItem(value: 'sort', icon: Icons.sort_rounded, label: '排序方式'),
          const GlassMenuDivider(),
          GlassMenuItem(
            value: 'select',
            icon: Icons.checklist_rounded,
            label: '選取書源',
            enabled: provider.totalSourceCount > 0,
          ),
          const GlassMenuDivider(),
          GlassMenuItem(
            value: 'import_url',
            icon: Icons.language,
            label: '網路匯入',
            enabled: importEnabled && mutationEnabled,
          ),
          GlassMenuItem(
            value: 'import_file',
            icon: Icons.file_open_outlined,
            label: '本地匯入',
            enabled: importEnabled && mutationEnabled,
          ),
          GlassMenuItem(
            value: 'import_clipboard',
            icon: Icons.content_paste,
            label: '剪貼簿匯入',
            enabled: importEnabled && mutationEnabled,
          ),
          GlassMenuItem(
            value: 'new_source',
            icon: Icons.add_circle_outline,
            label: '新建書源',
            enabled: mutationEnabled,
          ),
          GlassMenuItem(
            value: 'manage_groups',
            icon: Icons.edit_note_outlined,
            label: '管理分組',
            enabled: mutationEnabled,
          ),
          const GlassMenuDivider(),
          GlassMenuItem(
            value: 'check_all',
            icon: Icons.playlist_add_check,
            label: '校驗所有書源',
            enabled: provider.totalSourceCount > 0 && mutationEnabled,
          ),
          GlassMenuItem(
            value: 'clear_check_marks',
            icon: Icons.layers_clear_outlined,
            label: '清除校驗標記',
            enabled: provider.totalSourceCount > 0 && mutationEnabled,
          ),
          GlassMenuItem(
            value: 'group_domain',
            icon: Icons.dns_outlined,
            label: '按域名分組',
            checked: provider.groupByDomain,
          ),
          const GlassMenuDivider(),
          GlassMenuItem(
            value: 'clear_invalid',
            icon: Icons.delete_sweep_outlined,
            label: '清理建議刪除來源',
            destructive: true,
            enabled: mutationEnabled,
          ),
          GlassMenuItem(
            value: 'clean_non_novel',
            icon: Icons.delete_forever_outlined,
            label: '刪除非小說源',
            destructive: true,
            enabled: mutationEnabled,
          ),
        ],
      ),
    );
  }
}
