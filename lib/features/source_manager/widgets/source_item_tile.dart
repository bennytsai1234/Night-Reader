import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:night_reader/shared/widgets/text/ui_text.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/source_check/check_source_service.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/context_ext.dart';
import 'package:night_reader/shared/widgets/glass/glass_menu.dart';
import 'package:night_reader/shared/widgets/lists/grouped_list.dart';
import 'package:night_reader/shared/widgets/lists/selection_circle.dart';
import 'package:night_reader/shared/widgets/lists/swipe_actions.dart';
import 'package:night_reader/shared/widgets/lists/trailing_swap.dart';
import 'package:night_reader/shared/layout/readable_width.dart';

import '../source_manager_provider.dart';

import 'package:night_reader/shared/widgets/text/drag_overflow_text.dart';
import 'package:night_reader/core/chinese/ui_language.dart';

/// 編輯模式左側勾選圈佔用的寬度（圈 22 + 間距）。
const double _kCheckSlotWidth = 22 + AppGrouped.iconGap;

/// 書源列和載入骨架共用同一套功能標籤，數量及「停發」寬度不可猜。
List<String> sourceFunctionTags(BookSource source) => [
  if (source.hasSearchUrl) '搜',
  if (source.hasExploreUrl) source.enabledExplore ? '發' : '停發',
  if (source.hasBookInfoRule) '詳',
  if (source.hasTocRule) '目',
  if (source.hasContentRule) '正',
];

/// 書源名稱旁的分組膠囊，書源列與骨架共用：分組以逗號相接。書源有狀態標籤時，
/// 校驗寫進分組的結果標記（「異常」「搜尋失效」……）不列，由狀態標籤顯示一次；
/// 沒有狀態標籤時（例如只有「異常」）照列，提示才不會整個不見。
String? sourceGroupLabel(BookSource source) => groupLabelOf(
  source.bookSourceGroup,
  hasStatus: source.runtimeHealth.category != SourceHealthCategory.healthy,
);

/// [sourceGroupLabel] 的字串版，骨架讀上次記下的分組時也照這個整理。
String? groupLabelOf(String? group, {required bool hasStatus}) {
  final groups = splitSourceGroups(group)
      .where((tag) => !hasStatus || !sourceRuntimeStatusTags.contains(tag));
  return groups.isEmpty ? null : groups.join(',');
}

/// 書源列與骨架共用的錯誤提示，遇到長訊息要留出相同的高度。
String? sourceErrorLine(BookSource source) {
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

/// 書源清單的一列（Telegram 聊天列表式）：左滑置頂／刪除、右滑編輯，
/// 長按浮起預覽與動作選單；編輯模式左側出現勾選圈，右側換成排序把手。
class SourceItemTile extends StatelessWidget {
  final BookSource source;
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

  /// 列底是否畫分隔線（同組最後一列不畫）；不畫時也是卡片的最後一列，
  /// 帶下圓角。
  final bool showSeparator;

  /// 分組卡片的第一列，帶上圓角。
  final bool firstInGroup;
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
    this.firstInGroup = false,
    this.mutationEnabled = true,
  });

  /// 照網站分組時卡片頂端那一段的高度：和上一組的組間距（第一組沒有）、
  /// 粗字網址列與它下面的分隔線；進場排隊的佔位照它加高。
  static double hostHeaderHeight(
    BuildContext context,
    String hostLabel, {
    required bool first,
  }) {
    final width =
        math.min(MediaQuery.sizeOf(context).width, ReadableWidth.maxWidth) -
        AppGrouped.margin * 2;
    final row = GroupedRow(
      title: hostLabel,
      heading: true,
      translateTitle: false,
      showChevron: false,
    ).skeletonShape(context, width: width);
    return (first ? 0 : AppGrouped.sectionGap) + row.height + AppGlass.hairline;
  }

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
            // 這一列被鎖住時（校驗、批次作業）選單裡的動作都不會生效，不開選單。
            onLongPress: editing || !mutationEnabled
                ? null
                : () => onLongPress(
                    globalRectOf(rowContext),
                    // 底色在預覽裡取，選單開著時系統切換深淺也跟著換。
                    Builder(
                      builder: (context) => Material(
                        color: AppChrome.of(context).groupedSurface,
                        child: _SourceRowContent(
                          source: source,
                          provider: provider,
                          isSelected: false,
                          editing: false,
                          mutationEnabled: false,
                          showSeparator: false,
                          // 預覽不接收觸控，開關保持一般外觀而非停用的淡色。
                          trailing: _enabledSwitch(context),
                        ),
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
                              label:
                                  '${context.ui('拖曳調整')} '
                                  '${source.bookSourceName} '
                                  '${context.ui('順序')}',
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
                  : _enabledSwitch(context),
            ),
          ),
        );
      },
    );

    final swipe = SwipeActions(
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
          color: AppTint.rust.color,
          destructive: true,
          onPressed: onDelete,
        ),
      ],
      child: row,
    );
    // 和其他分組清單一樣是左右內縮的圓角卡片，一列一列接起來（同
    // GroupedSliceItem）；滑出的動作也收在卡片裡。
    const corner = Radius.circular(AppGrouped.radius);
    final tile = Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppGrouped.margin),
      child: ClipRRect(
        borderRadius: BorderRadius.vertical(
          top: firstInGroup && !showHostHeader ? corner : Radius.zero,
          bottom: showSeparator ? Radius.zero : corner,
        ),
        child: swipe,
      ),
    );

    if (!showHostHeader) return tile;
    // 照網站分組時，網址是這張卡的第一列（粗字，ADR 0076）；第一組接在
    // 清單頂端，之後每組和上一組隔一段組間距。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ColoredBox(
          color: chrome.groupedBackground,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              AppGrouped.margin,
              index == 0 ? 0 : AppGrouped.sectionGap,
              AppGrouped.margin,
              0,
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: corner),
              child: Material(
                color: chrome.groupedSurface,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    GroupedRow(
                      title: hostLabel,
                      heading: true,
                      translateTitle: false,
                      showChevron: false,
                    ),
                    const InsetSeparator(indent: AppGrouped.rowPadding),
                  ],
                ),
              ),
            ),
          ),
        ),
        tile,
      ],
    );
  }

  Widget _enabledSwitch(BuildContext context) {
    return Semantics(
      label: '${source.bookSourceName} ${context.ui('啟用')}',
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

  final BookSource source;
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
          // 彈簧收回時會越過寬度 0；AnimatedSize 在排版時照約束定出尺寸，
          // 越過的部分自然停在 0，展開那側的回彈照舊。AnimatedSize 只在
          // 自己比子元件小時裁切，收合時子元件寬 0、勾選圈從 OverflowBox
          // 溢出，所以裁切由外層 ClipRect 照槽目前的寬度負責。
          ClipRect(
            child: AnimatedSize(
              duration: AppMotion.spring,
              curve: AppMotion.springCurve,
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: editing ? _kCheckSlotWidth : 0,
                child: OverflowBox(
                  // 列表列的高度不設上限，預設的 max 會把高度撐成無限大。
                  fit: OverflowBoxFit.deferToChild,
                  alignment: Alignment.centerLeft,
                  minWidth: _kCheckSlotWidth,
                  maxWidth: _kCheckSlotWidth,
                  child: SelectionCircle(selected: isSelected),
                ),
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
                      child: DragOverflowText(
                        child: UiText(
                          source.bookSourceName,
                          translate: false,
                          style: AppTextStyles.bodyBase.copyWith(
                            height: 1.3,
                            fontWeight: FontWeight.w500,
                            color: scheme.onSurface,
                          ),
                          maxLines: 1,
                        ),
                      ),
                    ),
                    if (sourceGroupLabel(source) case final group?)
                      Padding(
                        padding: const EdgeInsets.only(left: AppSpacing.sm),
                        child: _GroupCapsule(group),
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
                DragOverflowText(
                  child: UiText(
                    source.bookSourceUrl,
                    translate: false,
                    style: AppTextStyles.bodySm.copyWith(
                      height: 1.3,
                      color: chrome.sectionText,
                    ),
                    maxLines: 1,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                _buildTags(context, chrome),
                if (checkProgress != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _buildCheckProgress(context, checkProgress),
                ],
                if (errorLine != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  DragOverflowText(
                    child: UiText(
                      errorLine,
                      style: AppTextStyles.labelSm.copyWith(
                        height: 1.3,
                        color: context.warning,
                      ),
                      maxLines: 2,
                    ),
                  ),
                ],
              ],
            ),
          ),
          TrailingSwap(
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
      child: UiText(
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
    final tags = sourceFunctionTags(source);

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
            child: UiText(
              tag,
              translate: false,
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
          child: DragOverflowText(
            child: UiText(
              progress.message,
              style: AppTextStyles.labelSm.copyWith(
                height: 1.3,
                color: color,
                fontWeight: progress.isFinal
                    ? FontWeight.w600
                    : FontWeight.w500,
              ),
              maxLines: 2,
            ),
          ),
        ),
      ],
    );
  }

  String? get _errorLine => sourceErrorLine(source);
}

/// 書源名稱旁的分組名稱，取代原本的「[分組]」括號字。
class _GroupCapsule extends StatelessWidget {
  const _GroupCapsule(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final chrome = AppChrome.of(context);
    return ConstrainedBox(
      // 分組名稱可能很長，限寬才不會把書源名稱擠掉。
      constraints: const BoxConstraints(maxWidth: 120),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 2,
        ),
        decoration: BoxDecoration(
          color: chrome.sectionText.withValues(alpha: 0.1),
          borderRadius: AppRadius.pillShape,
        ),
        child: DragOverflowText(
          child: UiText(
            label,
            translate: false,
            maxLines: 1,
            style: AppTextStyles.labelXs.copyWith(
              height: 1.15,
              color: chrome.sectionText,
            ),
          ),
        ),
      ),
    );
  }
}
