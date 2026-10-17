import 'package:flutter/material.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';

/// 佔位文字條的長度，輪流使用，看起來才像不同的書源。
const List<double> _nameWidths = [0.4, 0.55, 0.3, 0.5, 0.35, 0.45];
const List<double> _urlWidths = [0.6, 0.45, 0.7, 0.5, 0.65, 0.4];

/// 書源管理第一次讀取時的骨架：和書源列（`SourceItemTile`）同樣的分組
/// 卡片與每列的名稱、網址、功能標籤和列尾開關，換成清單時版面不跳動。
class SourceListSkeleton extends StatelessWidget {
  const SourceListSkeleton({
    super.key,
    required this.padding,
    required this.count,
  });

  /// 與書源清單相同的內距。
  final EdgeInsets padding;

  /// 上次讀完時的書源數；null（沒有紀錄）時鋪滿畫面。
  final int? count;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    double lineHeight(TextStyle style, double height) =>
        scaler.scale(style.fontSize!) * height;
    final tagHeight = lineHeight(AppTextStyles.labelXs, 1.15) + 4;
    final rowHeight =
        AppSpacing.md * 2 +
        lineHeight(AppTextStyles.bodyBase, 1.3) +
        2 +
        lineHeight(AppTextStyles.bodySm, 1.3) +
        AppSpacing.xs +
        tagHeight;
    return ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fill =
              ((constraints.maxHeight - padding.vertical) / rowHeight).ceil() +
              1;
          final rows = count == null ? fill : count!.clamp(0, fill);
          // 書源比一個畫面多時卡片延伸出畫面，底部不收圓角。
          final cardCount = count == null || count! > fill ? rows + 1 : rows;
          return ListView.builder(
            physics: const NeverScrollableScrollPhysics(),
            padding: padding,
            itemCount: rows,
            itemBuilder: (context, index) => GroupedSliceItem(
              index: index,
              count: cardCount,
              child: _SourceRowSkeleton(seed: index, tagHeight: tagHeight),
            ),
          );
        },
      ),
    );
  }
}

class _SourceRowSkeleton extends StatelessWidget {
  const _SourceRowSkeleton({required this.seed, required this.tagHeight});

  final int seed;
  final double tagHeight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppGrouped.rowPadding,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SkeletonLine(
                  style: AppTextStyles.bodyBase.copyWith(height: 1.3),
                  widthFactor: _nameWidths[seed % _nameWidths.length],
                ),
                const SizedBox(height: 2),
                SkeletonLine(
                  style: AppTextStyles.bodySm.copyWith(height: 1.3),
                  widthFactor: _urlWidths[seed % _urlWidths.length],
                ),
                const SizedBox(height: AppSpacing.xs),
                // 功能標籤（搜、詳、目、正）是一字的小方塊。
                Row(
                  children: [
                    for (var i = 0; i < 3 + seed % 2; i++) ...[
                      if (i > 0) const SizedBox(width: AppSpacing.xs),
                      SkeletonBox(width: tagHeight, height: tagHeight),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(left: AppSpacing.md),
            child: SkeletonBox(
              width: GroupedSwitch.trackWidth,
              height: GroupedSwitch.trackHeight,
              borderRadius: AppRadius.pillShape,
            ),
          ),
        ],
      ),
    );
  }
}
