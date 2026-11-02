import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:night_reader/shared/widgets/grouped_list_skeleton.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';

import 'explore_book_item.dart';

/// 佔位文字條的長度，輪流使用，看起來才像不同的內容。
const List<double> _widths = [0.45, 0.6, 0.35, 0.55, 0.4, 0.5];

/// 發現頁書源清單的骨架：一張分組卡片，每列一條書源名稱。
class ExploreSourceListSkeleton extends StatelessWidget {
  const ExploreSourceListSkeleton({
    super.key,
    required this.padding,
    this.count,
    this.names = const [],
  });

  /// 與書源清單相同的內距。
  final EdgeInsets padding;

  /// 尚未讀取時的上次列數；null 才需要鋪滿畫面。
  final int? count;

  /// 這輪資料回來後，可用真正名稱而不是固定比例重算最後一幀的骨架。
  final List<String> names;

  @override
  Widget build(BuildContext context) {
    final rowHeight = math.max(
      AppGrouped.rowMinHeight,
      MediaQuery.textScalerOf(context)
              .scale(AppTextStyles.bodyBase.fontSize!) *
          1.3 +
          AppSpacing.md * 2,
    );
    return ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fill = _countToFill(
            constraints.maxHeight - padding.vertical,
            rowHeight,
          );
          final rows = count == null ? fill : count!.clamp(0, fill);
          final cardCount = count == null || count! > fill ? rows + 1 : rows;
          return ListView.builder(
            // 骨架呼吸時整片每一幀都重畫，每列各一層只多了每一幀的開銷。
            addRepaintBoundaries: false,
            physics: const NeverScrollableScrollPhysics(),
            padding: padding,
            itemCount: rows,
            itemBuilder: (context, index) => GroupedSliceItem(
              index: index,
              count: cardCount,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: AppGrouped.rowMinHeight,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppGrouped.rowPadding,
                    vertical: AppSpacing.md,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: index < names.length
                            ? LayoutBuilder(
                                builder: (context, constraints) {
                                  final text = GroupedItemShape.text(
                                    context,
                                    names[index],
                                    style: AppTextStyles.bodyBase.copyWith(
                                      height: 1.3,
                                    ),
                                    width: constraints.maxWidth,
                                    maxLines: 1,
                                  );
                                  return SkeletonShapes(
                                    height: text.height,
                                    shapes: (_) => text.marks,
                                  );
                                },
                              )
                            : SkeletonLine(
                                style: AppTextStyles.bodyBase.copyWith(
                                  height: 1.3,
                                ),
                                widthFactor: _widths[index % _widths.length],
                              ),
                      ),
                      // 真正的發現書源列右側永遠有一個 22×22 展開箭頭。
                      const SkeletonBox(
                        width: 22,
                        height: 22,
                        borderRadius: BorderRadius.all(Radius.circular(5.5)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 發現分類書單的骨架：與 [ExploreBookItem] 同樣的封面與文字位置。
class ExploreBookListSkeleton extends StatelessWidget {
  const ExploreBookListSkeleton({super.key, required this.padding});

  /// 與書單相同的內距。
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    const rowHeight = ExploreBookItem.coverHeight + AppSpacing.md * 2;
    return ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final count = _countToFill(
            constraints.maxHeight - padding.vertical,
            rowHeight,
          );
          return ListView.separated(
            // 同書源列表的骨架：整片每一幀都重畫，不每列各一層。
            addRepaintBoundaries: false,
            physics: const NeverScrollableScrollPhysics(),
            padding: padding,
            itemCount: count,
            separatorBuilder: (_, _) =>
                const InsetSeparator(indent: ExploreBookItem.textIndent),
            itemBuilder: (context, index) =>
                _BookRowSkeleton(seed: index % _widths.length),
          );
        },
      ),
    );
  }
}

class _BookRowSkeleton extends StatelessWidget {
  const _BookRowSkeleton({required this.seed});

  final int seed;

  @override
  Widget build(BuildContext context) {
    final title = AppTextStyles.bodyBase.copyWith(height: 1.3);
    final meta = AppTextStyles.bodySm.copyWith(height: 1.35);
    double width(int offset) => _widths[(seed + offset) % _widths.length];
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppGrouped.margin,
        AppSpacing.md,
        AppGrouped.margin,
        AppSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonBox(
            width: ExploreBookItem.coverWidth,
            height: ExploreBookItem.coverHeight,
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonLine(style: title, widthFactor: width(0) + 0.2),
                const SizedBox(height: 2),
                SkeletonLine(style: meta, widthFactor: width(1)),
                const SizedBox(height: 2),
                SkeletonLine(style: meta, widthFactor: width(2) + 0.35),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

int _countToFill(double extent, double itemExtent) =>
    extent <= 0 ? 1 : (extent / itemExtent).ceil();
