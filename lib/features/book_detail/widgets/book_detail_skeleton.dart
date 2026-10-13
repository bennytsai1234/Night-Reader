import 'package:flutter/material.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';

/// 書籍詳情載入中，頁首以下還不知道的部分：資訊分組、簡介與目錄的骨架。
/// 放在 [Skeleton] 底下才會呼吸。
class BookDetailSkeleton extends StatelessWidget {
  const BookDetailSkeleton({super.key});

  /// 目錄列的佔位長度，輪流使用。
  static const List<double> _chapterWidths = [0.55, 0.4, 0.65, 0.5, 0.45];
  static const int _chapterRows = 8;

  @override
  Widget build(BuildContext context) {
    final rowStyle = AppTextStyles.bodyBase.copyWith(height: 1.3);
    Widget row(double widthFactor) => ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppGrouped.rowMinHeight),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppGrouped.rowPadding,
          vertical: AppSpacing.md,
        ),
        child: SkeletonLine(style: rowStyle, widthFactor: widthFactor),
      ),
    );
    final introStyle = AppTextStyles.bodyBase.copyWith(height: 1.6);
    return ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GroupedSection(children: [row(0.5), row(0.35), row(0.6)]),
          GroupedSection(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppGrouped.rowPadding,
                  vertical: AppSpacing.md,
                ),
                child: Column(
                  children: [
                    for (final width in const [1.0, 1.0, 0.95, 0.6])
                      SkeletonLine(style: introStyle, widthFactor: width),
                  ],
                ),
              ),
            ],
          ),
          GroupedSection(
            children: [
              for (var i = 0; i < _chapterRows; i++)
                row(_chapterWidths[i % _chapterWidths.length]),
            ],
          ),
        ],
      ),
    );
  }
}
