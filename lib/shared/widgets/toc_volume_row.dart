import 'package:flutter/material.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';

/// 卷內的章往右縮的寬度：一個字。
const double tocChapterIndent = 15;

/// 目錄裡分卷那一列：和章節一樣高，粗體卷名，右側章數與收起／展開的
/// 箭頭，點了收起或展開（docs/design/components.md「其他元件」）。[collapsed] 為 null 時不能
/// 收起（目錄在搜尋或倒序），只畫卷名與章數。
class TocVolumeRow extends StatelessWidget {
  const TocVolumeRow({
    super.key,
    required this.title,
    required this.count,
    this.collapsed,
    this.onToggle,
  });

  final String title;
  final int count;
  final bool? collapsed;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final collapsed = this.collapsed;
    return Semantics(
      expanded: collapsed == null ? null : !collapsed,
      child: GroupedRow(
        title: title,
        titleWidget: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.bodyBase.copyWith(
            height: 1.3,
            color: scheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
        value: '$count 章',
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
      ),
    );
  }
}
