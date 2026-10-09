import 'package:flutter/material.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';

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

  static const double _buttonSize = 34;

  @override
  Widget build(BuildContext context) {
    final count = provider.filteredChapters.length;
    final total = provider.totalChapterCount;
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
        size: _buttonSize,
        iconSize: 18,
        color: color,
        onPressed: onPressed,
      ),
    );

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        AppGrouped.margin + AppGrouped.rowPadding,
        AppGrouped.sectionGap - AppSpacing.md,
        AppGrouped.margin,
        AppSpacing.sm,
      ),
      sliver: SliverToBoxAdapter(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: GroupedSectionHeader(
                isSearching ? '搜尋結果（$count/$total 章）' : '目錄（共 $total 章）',
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
