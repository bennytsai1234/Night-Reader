import 'package:flutter/material.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/widgets/text/ui_text.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/glass/glass.dart';

import '../book_detail_provider.dart';

/// 目錄分組的組標題：章數與搜尋、清除搜尋、定位、排序四個小圓鈕。
class BookInfoTocBar extends StatelessWidget {
  final BookDetailProvider provider;
  final VoidCallback onSearch;
  final VoidCallback onLocateCurrent;

  const BookInfoTocBar({
    super.key,
    required this.provider,
    required this.onSearch,
    required this.onLocateCurrent,
  });

  /// 組標題右側小圓鈕的直徑；載入骨架照它畫佔位。
  static const double buttonSize = 34;

  @override
  Widget build(BuildContext context) {
    // 章數不算分卷。
    final count = provider.filteredChapters
        .where((chapter) => !chapter.isVolume)
        .length;
    final total = provider.tocVolumes.chapterCount;
    final isSearching = provider.hasActiveTocSearch;
    final primary = Theme.of(context).colorScheme.primary;

    Widget button({
      required IconData icon,
      required String tooltip,
      required VoidCallback onPressed,
      Color? color,
    }) => Padding(
      padding: const EdgeInsets.only(left: AppSpacing.sm),
      child: GlassIconButton(
        icon: icon,
        tooltip: tooltip,
        size: buttonSize,
        iconSize: 18,
        color: color,
        onPressed: onPressed,
        // 組標題在頁面底色上、跟著目錄淡入：模糊不會有差別，只會在淡入的
        // 最後一幀才糊上（ADR 0022）。
        blur: false,
      ),
    );

    // 章數是資料，用粗字（ADR 0076）；夾在簡介卡與目錄卡中間，上下一樣。
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        AppGrouped.margin + AppGrouped.rowPadding,
        AppGrouped.sectionGap,
        AppGrouped.margin,
        AppGrouped.sectionGap,
      ),
      sliver: SliverToBoxAdapter(
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: UiText(
                  isSearching ? '搜尋結果（$count/$total 章）' : '目錄（共 $total 章）',
                  style: AppTextStyles.bodyBase.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ),
            button(
              icon: Icons.search_rounded,
              tooltip: '搜尋目錄',
              onPressed: onSearch,
              color: isSearching ? primary : null,
            ),
            if (isSearching)
              button(
                icon: Icons.close_rounded,
                tooltip: '清除目錄搜尋',
                onPressed: provider.clearTocSearch,
              ),
            button(
              icon: Icons.my_location_rounded,
              tooltip: '定位目前閱讀章節',
              onPressed: onLocateCurrent,
            ),
            button(
              icon: provider.isReversed
                  ? Icons.vertical_align_top_rounded
                  : Icons.vertical_align_bottom_rounded,
              tooltip: provider.isReversed ? '目前倒序' : '目前正序',
              onPressed: provider.toggleSort,
              color: provider.isReversed ? primary : null,
            ),
          ],
        ),
      ),
    );
  }
}
