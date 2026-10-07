import 'package:flutter/material.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/context_ext.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/glass_menu.dart';
import '../source_manager_provider.dart';

/// 編輯模式底部的浮動玻璃工具列 — 對標 legado SelectActionBar。
/// 提供反選、刪除與其餘批次操作選單；全選放在導航頁首。
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

  /// 工具列本體高度（不含系統區與上下間距）。
  static const double height = AppGlass.buttonSize + AppSpacing.sm * 2;

  /// 清單底部需要讓出的高度（不含系統區）。
  static const double occupiedHeight =
      height + AppGlass.tabBarBottomGap + AppSpacing.md;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chrome = AppChrome.of(context);
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
    final selectionLabel =
        allCount == 0 && hasSelection
            ? '已選 $selectCount 個（目前篩選無項目）'
            : '$visibleSelectedCount/$allCount'
                '${hiddenSelectedCount > 0 ? '，另選 $hiddenSelectedCount 個' : ''}';

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: AppGlass.tabBarBottomGap),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppGlass.tabBarMaxWidth,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppGrouped.margin),
            child: SizedBox(
              height: height,
              child: GlassSurface(
                borderRadius: AppRadius.pillShape,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                  child: Row(
                    children: [
                      _BarTextButton(
                        label: '反選',
                        color: scheme.onSurface,
                        onTap:
                            allCount > 0 && !isBusy
                                ? provider.revertSelection
                                : null,
                      ),
                      Expanded(
                        child: Text(
                          selectionLabel,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.uiSm.copyWith(
                            color: chrome.sectionText,
                          ),
                        ),
                      ),
                      _BarTextButton(
                        label: '刪除',
                        color: context.danger,
                        onTap: actionsEnabled ? onDelete : null,
                      ),
                      if (actionsEnabled)
                        GlassMenuButton<String>(
                          tooltip: '更多批次操作',
                          entriesBuilder: (_) => _entries,
                          onSelected: _onMenuSelected,
                          child: _moreIcon(scheme.onSurface),
                        )
                      else
                        Tooltip(
                          message: isBusy ? '操作進行中' : '更多批次操作',
                          child: _moreIcon(
                            scheme.onSurface.withValues(alpha: 0.38),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _moreIcon(Color color) {
    return SizedBox.square(
      dimension: AppGlass.buttonSize,
      child: Icon(Icons.more_horiz_rounded, size: 22, color: color),
    );
  }

  static const List<GlassMenuEntry<String>> _entries = [
    GlassMenuItem(
      value: 'enable',
      icon: Icons.toggle_on_outlined,
      label: '啟用選中',
    ),
    GlassMenuItem(
      value: 'disable',
      icon: Icons.toggle_off_outlined,
      label: '禁用選中',
    ),
    GlassMenuDivider(),
    GlassMenuItem(value: 'add_group', icon: Icons.playlist_add, label: '加入分組'),
    GlassMenuItem(
      value: 'remove_group',
      icon: Icons.playlist_remove,
      label: '移出分組',
    ),
    GlassMenuItem(
      value: 'enable_explore',
      icon: Icons.travel_explore,
      label: '啟用發現',
    ),
    GlassMenuItem(
      value: 'disable_explore',
      icon: Icons.explore_off_outlined,
      label: '禁用發現',
    ),
    GlassMenuDivider(),
    GlassMenuItem(
      value: 'select_interval',
      icon: Icons.select_all,
      label: '連續選取',
    ),
    GlassMenuItem(value: 'top', icon: Icons.vertical_align_top, label: '置頂'),
    GlassMenuItem(
      value: 'bottom',
      icon: Icons.vertical_align_bottom,
      label: '置底',
    ),
    GlassMenuDivider(),
    GlassMenuItem(
      value: 'export',
      icon: Icons.file_download_outlined,
      label: '匯出選中',
    ),
    GlassMenuItem(value: 'share', icon: Icons.share_outlined, label: '分享選中'),
    GlassMenuDivider(),
    GlassMenuItem(
      value: 'check',
      icon: Icons.playlist_add_check,
      label: '校驗選中',
    ),
  ];

  void _onMenuSelected(String value) {
    switch (value) {
      case 'enable':
        onEnable();
      case 'disable':
        onDisable();
      case 'add_group':
        onAddGroup();
      case 'remove_group':
        onRemoveGroup();
      case 'enable_explore':
        onEnableExplore();
      case 'disable_explore':
        onDisableExplore();
      case 'select_interval':
        onSelectInterval();
      case 'top':
        onMoveToTop();
      case 'bottom':
        onMoveToBottom();
      case 'export':
        onExport();
      case 'share':
        onShare();
      case 'check':
        onCheckSource();
    }
  }
}

class _BarTextButton extends StatelessWidget {
  const _BarTextButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      child: PressScale(
        onTap: onTap,
        child: SizedBox(
          height: AppGlass.buttonSize,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Center(
              widthFactor: 1,
              child: Text(
                label,
                style: AppTextStyles.uiMd.copyWith(
                  color: color.withValues(alpha: enabled ? 1 : 0.38),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
