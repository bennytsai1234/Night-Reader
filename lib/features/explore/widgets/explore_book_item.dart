import 'package:flutter/material.dart';
import 'package:reader/core/models/search_book.dart';
import 'package:reader/shared/theme/app_tokens.dart';
import 'package:reader/core/widgets/book_cover_widget.dart';
import 'package:reader/shared/theme/context_ext.dart';
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
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面 (對標 Android ivCover)
            BookCoverWidget(
              coverUrl: book.coverUrl,
              bookName: book.name,
              author: book.author,
              width: 56,
              height: 75,
              borderRadius: AppRadius.cardXs,
            ),
            const SizedBox(width: 12),
            // 書籍信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 書名 (對標 Android tvName)
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          book.name,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isInBookshelf) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
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
                              const SizedBox(width: 4),
                              Text(
                                '書架',
                                style: theme.textTheme.labelSmall?.copyWith(
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
                  const SizedBox(height: 4),
                  // 作者 (對標 Android tvAuthor)
                  if (book.author != null && book.author!.isNotEmpty)
                    Text(
                      '作者: ${book.author}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 2),
                  // 最新章節 (對標 Android tvLasted)
                  if (book.latestChapterTitle != null &&
                      book.latestChapterTitle!.isNotEmpty)
                    Text(
                      '最新: ${book.latestChapterTitle}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: context.warning,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 2),
                  // 簡介 (對標 Android tvIntroduce)
                  if (book.intro != null && book.intro!.isNotEmpty)
                    Text(
                      book.intro!.replaceAll(RegExp(r'\s+'), ' ').trim(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 4),
                  // 分類標籤 (對標 Android llKind)
                  if (book.kind != null && book.kind!.isNotEmpty)
                    Wrap(
                      spacing: 4,
                      runSpacing: 2,
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

  /// 構建分類標籤 (對標 Android llKind.setLabels)
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
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.3),
          ),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          kind,
          style: TextStyle(
            fontSize: 10,
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
