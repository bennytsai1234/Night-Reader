import 'package:flutter/material.dart';
import 'package:night_reader/features/source_manager/ai_repair/repair_runs.dart';
import 'package:night_reader/shared/widgets/glass_menu.dart';

import '../source_manager_provider.dart';

/// 書源管理頁首的「更多」選單：頁首只放這一顆，標題才不會被擠到；
/// 分組篩選與排序在第一層各有一項，點了在同一處開出第二層。
class SourceManagerMenus {
  static const List<String> _statusFilters = [
    '全部',
    '已啟用',
    '已停用',
    '已啟用發現',
    '已停用發現',
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
    // 漫畫、有聲源和小說源混在同一個清單，篩得出來才找得到它們；沒有
    // 這類書源時灰掉（ADR 0059）。
    const GlassMenuDivider(),
    for (final filter in SourceManagerProvider.kindFilters.keys)
      GlassMenuItem(
        value: filter,
        label: filter,
        checked: provider.filterGroup == filter,
        enabled: provider.presentKindFilters.contains(filter),
      ),
    // 校驗結果和自己的分組分開：校驗完要挑出失效的書源一起停用或刪掉。
    // 「沒有異常」一直在，還沒校驗過時灰掉；下面的標記照書源上有的列。
    const GlassMenuDivider(),
    GlassMenuItem(
      value: SourceManagerProvider.noAbnormalFilter,
      label: SourceManagerProvider.noAbnormalFilter,
      checked: provider.filterGroup == SourceManagerProvider.noAbnormalFilter,
      enabled: provider.anySourceChecked,
    ),
    for (final tag in provider.checkResultTags)
      GlassMenuItem(
        value: tag,
        label: tag,
        checked: provider.filterGroup == tag,
      ),
    if (provider.userGroups.isNotEmpty) const GlassMenuDivider(),
    for (final group in provider.userGroups)
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
    // 每個網域一張卡也是清單怎麼排，和排序收在一起。
    const GlassMenuDivider(),
    GlassMenuItem(
      value: 'group_domain',
      label: '按域名分組',
      icon: Icons.dns_outlined,
      checked: provider.groupByDomain,
    ),
  ];

  /// 加入書源的選單項目：三種匯入與新建。
  static List<GlassMenuEntry<String>> _addEntries({
    required bool importEnabled,
    required bool mutationEnabled,
  }) => [
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
  ];

  /// 校驗與修復的選單項目；AI 服務設定放這裡當快速入口。
  static List<GlassMenuEntry<String>> _checkEntries(
    SourceManagerProvider provider, {
    required bool mutationEnabled,
  }) => [
    GlassMenuItem(
      value: 'check_all',
      icon: Icons.playlist_add_check,
      label: '校驗所有書源',
      enabled:
          provider.totalSourceCount > 0 &&
          mutationEnabled &&
          backgroundWorkIdle(),
    ),
    GlassMenuItem(
      value: 'clear_check_marks',
      icon: Icons.layers_clear_outlined,
      label: '清除校驗標記',
      enabled: provider.totalSourceCount > 0 && mutationEnabled,
    ),
    GlassMenuItem(
      value: 'repair_abnormal',
      icon: Icons.healing_outlined,
      label: '修復異常書源',
      // 整批修復跑著時也能按：打開它的進度頁。
      enabled:
          RepairRuns.instance.current is BatchRepairRun ||
          (provider.abnormalSourceUrls.isNotEmpty &&
              mutationEnabled &&
              canRepairBatch()),
    ),
    const GlassMenuItem(
      value: 'ai_settings',
      icon: Icons.auto_fix_high_outlined,
      label: 'AI 服務設定',
    ),
  ];

  /// 在「更多」鈕的位置接著開出第二層選單。
  static Future<void> _openSubmenu(
    BuildContext buttonContext,
    List<GlassMenuEntry<String>> entries,
    ValueChanged<String> onSelected,
  ) async {
    final value = await showGlassSubmenu<String>(buttonContext, entries);
    if (value != null) onSelected(value);
  }

  static Widget buildMoreMenu(
    BuildContext context,
    SourceManagerProvider provider, {
    required VoidCallback onImportUrl,
    required VoidCallback onImportFile,
    required VoidCallback onImportClipboard,
    required VoidCallback onManageGroups,
    required VoidCallback onNewSource,
    required VoidCallback onCheckAllSources,
    required VoidCallback onClearCheckMarks,
    required VoidCallback onAiRepairSettings,
    required VoidCallback onRepairAbnormal,
    required VoidCallback onDeleteByTags,
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
                switch (value) {
                  case 'desc':
                    provider.toggleSortDesc();
                  case 'group_domain':
                    provider.toggleGroupByDomain();
                  default:
                    provider.setSortMode(int.parse(value));
                }
              });
            case 'add':
              _openSubmenu(
                buttonContext,
                _addEntries(
                  importEnabled: importEnabled,
                  mutationEnabled: mutationEnabled,
                ),
                (value) => switch (value) {
                  'import_url' => onImportUrl(),
                  'import_file' => onImportFile(),
                  'import_clipboard' => onImportClipboard(),
                  _ => onNewSource(),
                },
              );
            case 'check':
              _openSubmenu(
                buttonContext,
                _checkEntries(provider, mutationEnabled: mutationEnabled),
                (value) => switch (value) {
                  'check_all' => onCheckAllSources(),
                  'clear_check_marks' => onClearCheckMarks(),
                  'repair_abnormal' => onRepairAbnormal(),
                  _ => onAiRepairSettings(),
                },
              );
            case 'delete_by_tags':
              onDeleteByTags();
          }
        },
        // 會展開的四項右邊是「›」；直接動作的只有刪除。
        entriesBuilder: (_) => [
          const GlassMenuItem(value: 'filter', label: '分組與篩選', submenu: true),
          const GlassMenuItem(value: 'sort', label: '排序方式', submenu: true),
          const GlassMenuDivider(),
          const GlassMenuItem(value: 'add', label: '加入書源', submenu: true),
          const GlassMenuItem(value: 'check', label: '校驗與修復', submenu: true),
          const GlassMenuDivider(),
          GlassMenuItem(
            value: 'delete_by_tags',
            icon: Icons.delete_sweep_outlined,
            label: '按標籤刪除',
            destructive: true,
            enabled: provider.totalSourceCount > 0 && mutationEnabled,
          ),
        ],
      ),
    );
  }
}
