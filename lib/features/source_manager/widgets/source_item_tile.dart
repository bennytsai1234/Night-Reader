import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:night_reader/core/models/book_source_part.dart';
import 'package:night_reader/core/models/source/book_source_logic.dart';
import 'package:night_reader/core/services/check_source_service.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/context_ext.dart';
import 'package:night_reader/shared/widgets/glass_menu.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:night_reader/shared/widgets/swipe_actions.dart';

import '../source_manager_provider.dart';

/// 編輯模式左側勾選圈佔用的寬度（圈 22 + 間距）。
const double _kCheckSlotWidth = 22 + AppGrouped.iconGap;

/// 書源清單的一列（Telegram 聊天列表式）：左滑置頂／刪除、右滑編輯，
/// 長按浮起預覽與動作選單；編輯模式左側出現勾選圈，右側換成排序把手。
class SourceItemTile extends StatelessWidget {
  final BookSourcePart source;
  final SourceManagerProvider provider;
  final bool isSelected;

  /// 是否處於批次選取（編輯）模式。
  final bool editing;
  final VoidCallback onTap;

  /// 長按：傳回列在螢幕上的範圍與預覽用的列外觀。
  final void Function(Rect sourceRect, Widget preview) onLongPress;
  final VoidCallback onEdit;
  final VoidCallback onMoveToTop;
  final VoidCallback onDelete;
  final ValueChanged<bool> onEnabledChanged;
  final int? index;
  final bool showHostHeader;
  final String hostLabel;

  /// 列底是否畫分隔線（同組最後一列不畫）。
  final bool showSeparator;
  final bool mutationEnabled;

  const SourceItemTile({
    super.key,
    required this.source,
    required this.provider,
    required this.isSelected,
    required this.editing,
    required this.onTap,
    required this.onLongPress,
    required this.onEdit,
    required this.onMoveToTop,
    required this.onDelete,
    required this.onEnabledChanged,
    this.index,
    this.showHostHeader = false,
    this.hostLabel = '',
    this.showSeparator = true,
    this.mutationEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final chrome = AppChrome.of(context);
    final canDrag =
        editing && provider.canReorder && mutationEnabled && index != null;

    final row = Builder(
      builder: (rowContext) {
        return Material(
          color: chrome.groupedSurface,
          child: InkWell(
            onTap: mutationEnabled ? onTap : null,
            onLongPress: editing
                ? null
                : () => onLongPress(
                    globalRectOf(rowContext),
                    Material(
                      color: chrome.groupedSurface,
                      child: _SourceRowContent(
                        source: source,
                        provider: provider,
                        isSelected: false,
                        editing: false,
                        mutationEnabled: false,
                        showSeparator: false,
                        // 預覽不接收觸控，開關保持一般外觀而非停用的淡色。
                        trailing: _enabledSwitch(),
                      ),
                    ),
                  ),
            child: _SourceRowContent(
              source: source,
              provider: provider,
              isSelected: isSelected,
              editing: editing,
              mutationEnabled: mutationEnabled,
              showSeparator: showSeparator,
              trailing: editing
                  ? (canDrag
                        ? ReorderableDragStartListener(
                            index: index!,
                            child: Semantics(
                              label: '拖曳調整 ${source.bookSourceName} 順序',
                              child: SizedBox.square(
                                dimension: AppGrouped.rowMinHeight,
                                child: Icon(
                                  Icons.drag_handle_rounded,
                                  size: 22,
                                  color: chrome.sectionText,
                                ),
                              ),
                            ),
                          )
                        : null)
                  : _enabledSwitch(),
            ),
          ),
        );
      },
    );

    final tile = SwipeActions(
      enabled: !editing && mutationEnabled,
      leading: [
        SwipeAction(
          label: '編輯',
          icon: Icons.edit_outlined,
          color: AppTint.azurite.color,
          onPressed: onEdit,
        ),
      ],
      trailing: [
        SwipeAction(
          label: '置頂',
          icon: Icons.vertical_align_top_rounded,
          color: AppTint.tea.color,
          onPressed: onMoveToTop,
        ),
        SwipeAction(
          label: '刪除',
          icon: Icons.delete_outline_rounded,
          color: context.danger,
          destructive: true,
          onPressed: onDelete,
        ),
      ],
      child: row,
    );

    if (!showHostHeader) return tile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          color: chrome.groupedBackground,
          padding: const EdgeInsets.fromLTRB(
            AppGrouped.margin,
            AppSpacing.xl,
            AppGrouped.margin,
            AppSpacing.sm,
          ),
          child: GroupedSectionHeader(hostLabel),
        ),
        tile,
      ],
    );
  }

  Widget _enabledSwitch() {
    return Semantics(
      label: '${source.bookSourceName} 啟用',
      child: GroupedSwitch(
        value: source.enabled,
        onChanged: mutationEnabled ? onEnabledChanged : null,
      ),
    );
  }
}

class _SourceRowContent extends StatelessWidget {
  const _SourceRowContent({
    required this.source,
    required this.provider,
    required this.isSelected,
    required this.editing,
    required this.mutationEnabled,
    required this.showSeparator,
    required this.trailing,
  });

  final BookSourcePart source;
  final SourceManagerProvider provider;
  final bool isSelected;
  final bool editing;
  final bool mutationEnabled;
  final bool showSeparator;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final chrome = AppChrome.of(context);
    final scheme = Theme.of(context).colorScheme;
    final checkProgress = provider.checkService.progressOf(
      source.bookSourceUrl,
    );
    final errorLine = checkProgress == null ? _errorLine : null;
    final textStart = AppGrouped.rowPadding + (editing ? _kCheckSlotWidth : 0);

    final content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppGrouped.rowPadding,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          // 編輯模式的勾選圈從左側滑入。
          ClipRect(
            child: AnimatedContainer(
              duration: AppMotion.spring,
              curve: AppMotion.springCurve,
              width: editing ? _kCheckSlotWidth : 0,
              alignment: Alignment.centerLeft,
              child: OverflowBox(
                // 列表列的高度不設上限，預設的 max 會把高度撐成無限大。
                fit: OverflowBoxFit.deferToChild,
                alignment: Alignment.centerLeft,
                minWidth: _kCheckSlotWidth,
                maxWidth: _kCheckSlotWidth,
                child: _SelectionCircle(selected: isSelected),
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        _displayNameGroup(),
                        style: AppTextStyles.bodyBase.copyWith(
                          height: 1.3,
                          fontWeight: FontWeight.w500,
                          color: scheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (source.hasExploreUrl)
                      Padding(
                        padding: const EdgeInsets.only(left: AppSpacing.sm),
                        child: Icon(
                          Icons.circle,
                          size: 8,
                          color: source.enabledExplore
                              ? context.success
                              : chrome.sectionText,
                        ),
                      ),
                    if (source.runtimeHealth.category !=
                        SourceHealthCategory.healthy)
                      Padding(
                        padding: const EdgeInsets.only(left: AppSpacing.sm),
                        child: _buildStatusTag(context, source.runtimeHealth),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  source.bookSourceUrl,
                  style: AppTextStyles.bodySm.copyWith(
                    height: 1.3,
                    color: chrome.sectionText,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.xs),
                _buildTags(context, chrome),
                if (checkProgress != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _buildCheckProgress(context, checkProgress),
                ],
                if (errorLine != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    errorLine,
                    style: AppTextStyles.labelSm.copyWith(
                      height: 1.3,
                      color: context.warning,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          AnimatedSwitcher(
            duration: AppMotion.fade,
            switchInCurve: AppMotion.fadeCurve,
            switchOutCurve: AppMotion.fadeCurve,
            child: trailing == null
                ? const SizedBox.shrink()
                : Padding(
                    key: ValueKey(editing),
                    padding: const EdgeInsets.only(left: AppSpacing.md),
                    child: trailing,
                  ),
          ),
        ],
      ),
    );

    return Semantics(
      selected: editing ? isSelected : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ColoredBox(
            color: isSelected && editing
                ? scheme.primary.withValues(alpha: 0.06)
                : Colors.transparent,
            child: content,
          ),
          if (showSeparator)
            AnimatedPadding(
              duration: AppMotion.spring,
              curve: AppMotion.springCurve,
              padding: EdgeInsetsDirectional.only(start: textStart),
              child: Container(
                height: AppGlass.hairline,
                color: chrome.separator,
              ),
            ),
        ],
      ),
    );
  }

  String _displayNameGroup() {
    final group = source.bookSourceGroup;
    if (group != null && group.isNotEmpty) {
      return '${source.bookSourceName} [$group]';
    }
    return source.bookSourceName;
  }

  Widget _buildStatusTag(BuildContext context, SourceRuntimeHealth health) {
    final color = health.cleanupCandidate
        ? context.danger
        : health.quarantined
        ? context.warning
        : AppChrome.of(context).sectionText;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadius.cardXs,
      ),
      child: Text(
        health.label,
        style: AppTextStyles.labelXs.copyWith(
          height: 1.15,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildTags(BuildContext context, AppChrome chrome) {
    final tags = <String>[];
    if (source.hasSearchUrl) tags.add('搜');
    if (source.hasExploreUrl) tags.add(source.enabledExplore ? '發' : '停發');
    if (source.hasBookInfoRule) tags.add('詳');
    if (source.hasTocRule) tags.add('目');
    if (source.hasContentRule) tags.add('正');

    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        for (final tag in tags)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: chrome.sectionText.withValues(alpha: 0.1),
              borderRadius: AppRadius.cardXs,
            ),
            child: Text(
              tag,
              style: AppTextStyles.labelXs.copyWith(
                height: 1.15,
                color: chrome.sectionText,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCheckProgress(
    BuildContext context,
    SourceCheckProgress progress,
  ) {
    final color = progress.isFinal
        ? (progress.hasIssue ? context.warning : context.success)
        : Theme.of(context).colorScheme.primary;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2, right: AppSpacing.sm),
          child: progress.isFinal
              ? Icon(
                  progress.hasIssue
                      ? Icons.info_outline_rounded
                      : Icons.check_circle_rounded,
                  size: 14,
                  color: color,
                )
              : SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color,
                  ),
                ),
        ),
        Expanded(
          child: Text(
            progress.message,
            style: AppTextStyles.labelSm.copyWith(
              height: 1.3,
              color: color,
              fontWeight: progress.isFinal ? FontWeight.w600 : FontWeight.w500,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  String? get _errorLine {
    final comment = source.bookSourceComment?.trim();
    if (comment == null || comment.isEmpty) return null;
    for (final line in comment.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('// Error:')) {
        return trimmed.replaceFirst('// Error:', '').trim();
      }
    }
    return null;
  }
}

/// Telegram 編輯模式的圓形勾選：選中為主色實心圈加白勾，未選為髮絲空心圈。
class _SelectionCircle extends StatelessWidget {
  const _SelectionCircle({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chrome = AppChrome.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: AnimatedContainer(
        duration: AppMotion.menu,
        curve: AppMotion.menuCurve,
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? scheme.primary : Colors.transparent,
          border: Border.all(
            color: selected ? scheme.primary : chrome.sectionText,
            width: 1.5,
          ),
        ),
        child: selected
            ? Icon(Icons.check_rounded, size: 16, color: scheme.onPrimary)
            : null,
      ),
    );
  }
}
