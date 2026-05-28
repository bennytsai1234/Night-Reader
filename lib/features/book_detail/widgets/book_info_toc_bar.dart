import 'package:flutter/material.dart';
import 'package:reader/shared/theme/app_text_styles.dart';
import 'package:reader/shared/theme/app_tokens.dart';
import '../book_detail_provider.dart';

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

  @override
  Widget build(BuildContext context) {
    final count = provider.filteredChapters.length;
    final total = provider.totalChapterCount;
    final isSearching = count != total;

    return SliverPadding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      sliver: SliverToBoxAdapter(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              isSearching ? '搜尋結果 ($count/$total 章)' : '目錄 (共 $total 章)',
              style: AppTextStyles.bodyMd.copyWith(fontWeight: FontWeight.bold),
            ),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.search, size: 22),
                  onPressed: onSearch,
                  tooltip: '搜尋目錄',
                ),
                IconButton(
                  icon: const Icon(Icons.my_location, size: 22),
                  onPressed: onLocateCurrent,
                  tooltip: '定位目前閱讀章節',
                ),
                IconButton(
                  icon: Icon(
                    provider.isReversed
                        ? Icons.vertical_align_top
                        : Icons.vertical_align_bottom,
                    size: 22,
                    color:
                        provider.isReversed
                            ? Theme.of(context).colorScheme.primary
                            : null,
                  ),
                  onPressed: provider.toggleSort,
                  tooltip: provider.isReversed ? '目前倒序' : '目前正序',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
