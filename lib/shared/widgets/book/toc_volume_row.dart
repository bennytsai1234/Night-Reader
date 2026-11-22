import 'package:flutter/material.dart';
import 'package:night_reader/shared/widgets/text/ui_text.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/widgets/lists/grouped_list.dart';
import 'package:night_reader/shared/widgets/skeleton/grouped_list_skeleton.dart';
import 'package:night_reader/shared/widgets/text/drag_overflow_text.dart';

/// 卷內的章往右縮的寬度：一個字。
const double tocChapterIndent = 15;

/// 目錄裡分卷那一列：和章節一樣高，粗體卷名，右側章數與收起／展開的
/// 箭頭，點了收起或展開（docs/design/components.md「其他元件」）。[collapsed] 為 null 時不能
/// 收起（目錄在搜尋或倒序），只畫卷名與章數。
class TocVolumeRow extends StatelessWidget implements GroupedSkeletonItem {
  const TocVolumeRow({
    super.key,
    required this.title,
    required this.count,
    this.collapsed,
    this.onToggle,
    this.unit = '章',
  });

  final String title;
  final int count;
  final bool? collapsed;
  final VoidCallback? onToggle;

  /// 數量的單位：書的目錄是「章」，有聲書是「集」。
  final String unit;

  @override
  GroupedItemShape skeletonShape(
    BuildContext context, {
    required double width,
  }) => _row(context).skeletonShape(context, width: width);

  @override
  Widget build(BuildContext context) {
    final collapsed = this.collapsed;
    return Semantics(
      expanded: collapsed == null ? null : !collapsed,
      child: _row(context),
    );
  }

  GroupedRow _row(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final collapsed = this.collapsed;
    return GroupedRow(
      title: title,
      translateTitle: false,
      // 卷名是書的資料，照閱讀偏好的繁簡轉換（ADR 0066）。
      titleWidget: DragOverflowText(
        child: UiText(
          title,
          translate: false,
          maxLines: 1,
          style: AppTextStyles.bodyBase.copyWith(
            height: 1.3,
            color: scheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      value: '$count $unit',
      trailing: collapsed == null
          ? null
          : Icon(
              collapsed
                  ? Icons.keyboard_arrow_down_rounded
                  : Icons.keyboard_arrow_up_rounded,
              size: 22,
              color: scheme.onSurfaceVariant,
            ),
      showChevron: false,
      onTap: collapsed == null ? null : onToggle,
    );
  }
}
