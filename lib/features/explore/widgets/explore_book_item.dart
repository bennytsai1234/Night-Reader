import 'package:flutter/material.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/core/widgets/book_cover_widget.dart';
import 'package:night_reader/shared/theme/context_ext.dart';
import '../../book_detail/book_detail_page.dart';

/// ExploreBookItem - 探索結果書籍項目
/// (對標 Android ExploreShowAdapter + item_search 佈局)
///
/// 列表式展示：封面、書名、作者、最新章節、簡介、分類標籤。
class ExploreBookItem extends StatelessWidget {
  final SearchBook book;
  final bool isInBookshelf;
  final String? sourceName;

  const ExploreBookItem({
    super.key,
    required this.book,
    this.isInBookshelf = false,
    this.sourceName,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: () => _navigateToDetail(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BookCoverWidget(
              coverUrl: book.coverUrl,
              bookName: book.name,
              author: book.author,
              width: 56,
              height: 75,
              borderRadius: AppRadius.cardXs,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          book.name,
                          style: theme.textTheme.titleSmall?.copyWith(
                            height: 1.3,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isInBookshelf) ...[
                        const SizedBox(width: AppSpacing.sm),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: AppRadius.pillShape,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.library_add_check,
                                size: 12,
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              Text(
                                '書架',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  height: 1.2,
                                  color: theme.colorScheme.onPrimaryContainer,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  if (book.author != null && book.author!.isNotEmpty)
                    Text(
                      '作者: ${book.author}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        height: 1.4,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 2),
                  if (book.latestChapterTitle != null &&
                      book.latestChapterTitle!.isNotEmpty)
                    Text(
                      '最新: ${book.latestChapterTitle}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        height: 1.4,
                        color: context.warning,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 2),
                  if (book.intro != null && book.intro!.isNotEmpty)
                    Text(
                      book.intro!.replaceAll(RegExp(r'\s+'), ' ').trim(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        height: 1.45,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: AppSpacing.xs),
                  if (book.kind != null && book.kind!.isNotEmpty)
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: _buildKindTags(theme),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildKindTags(ThemeData theme) {
    final kinds =
        book.kind!
            .split(RegExp(r'[,，]'))
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .take(4)
            .toList();

    return kinds.map((kind) {
      return Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 2,
        ),
        decoration: BoxDecoration(
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.3),
          ),
          borderRadius: AppRadius.cardXs,
        ),
        child: Text(
          kind,
          style: theme.textTheme.labelSmall?.copyWith(
            height: 1.2,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }).toList();
  }

  void _navigateToDetail(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => BookDetailPage(
              searchBook: AggregatedSearchBook(
                book: book,
                sources: [book.originName ?? sourceName ?? '發現'],
              ),
            ),
      ),
    );
  }
}
