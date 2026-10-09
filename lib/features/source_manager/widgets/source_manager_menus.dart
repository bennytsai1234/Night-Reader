import 'package:flutter/material.dart';
import 'package:night_reader/shared/widgets/glass_menu.dart';

import '../source_manager_provider.dart';

/// 書源管理頁首的玻璃選單按鈕。
class SourceManagerMenus {
  static const List<String> _statusFilters = [
    '全部',
    '已啟用',
    '已禁用',
    '已啟用發現',
    '已禁用發現',
    '無分組',
  ];

  static Widget buildGroupMenu(
    BuildContext context,
    SourceManagerProvider provider, {
    required VoidCallback onManageGroups,
  }) {
    return GlassMenuButton<String>(
      icon: Icons.folder_outlined,
      tooltip: '分組與篩選',
      onSelected: (value) {
        if (value == 'manage_groups') {
          onManageGroups();
          return;
        }
        provider.setFilterGroup(value);
      },
      entriesBuilder: (_) => [
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
      ],
    );
  }

  static Widget buildSortMenu(
    BuildContext context,
    SourceManagerProvider provider,
  ) {
    const modes = ['手動排序', '自動排序', '按名稱', '按網址', '按更新時間'];
    return GlassMenuButton<String>(
      icon: Icons.sort_rounded,
      tooltip: '排序方式',
      onSelected: (value) {
        if (value == 'desc') {
          provider.toggleSortDesc();
        } else {
          provider.setSortMode(int.parse(value));
        }
      },
      entriesBuilder: (_) => [
        GlassMenuItem(
          value: 'desc',
          label: '倒序排列',
          icon: Icons.swap_vert_rounded,
          checked: provider.sortDesc,
        ),
        const GlassMenuDivider(),
        for (var i = 0; i < modes.length; i++)
          GlassMenuItem(
            value: '$i',
            label: modes[i],
            checked: provider.sortMode == i,
          ),
      ],
    );
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
    required Function(SourceManagerProvider) onClearInvalid,
    required Function(SourceManagerProvider) onDeleteNonNovel,
    bool importEnabled = true,
    bool mutationEnabled = true,
  }) {
    return GlassMenuButton<String>(
      tooltip: '更多操作',
      onSelected: (value) {
        switch (value) {
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
    );
  }
}
