import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/core/widgets/book_cover_widget.dart';
import 'package:night_reader/shared/theme/context_ext.dart';
import '../search_provider.dart';
import '../../book_detail/book_detail_page.dart';

class SearchResultItem extends StatefulWidget {
  final AggregatedSearchBook result;
  final bool isInBookshelf;

  const SearchResultItem({
    super.key,
    required this.result,
    this.isInBookshelf = false,
  });

  @override
  State<SearchResultItem> createState() => _SearchResultItemState();
}

class _SearchResultItemState extends State<SearchResultItem> {
  bool _sourcesExpanded = false;

  @override
  Widget build(BuildContext context) {
    final book = widget.result.book;
    final sourceCount = widget.result.sources.length;
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      leading: BookCoverWidget(
        coverUrl: book.coverUrl,
        bookName: book.name,
        author: book.author,
        width: 45,
        height: 60,
        borderRadius: AppRadius.cardXs,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              book.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                height: 1.3,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (widget.isInBookshelf) ...[
            Container(
              margin: const EdgeInsets.only(left: AppSpacing.sm),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: AppRadius.cardMd,
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
                    style: AppTextStyles.labelXs.copyWith(
                      height: 1.2,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (sourceCount > 1)
            Container(
              margin: const EdgeInsets.only(left: AppSpacing.sm),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: AppRadius.cardMd,
              ),
              child: Text(
                '$sourceCount 個書源',
                style: AppTextStyles.labelXs.copyWith(
                  height: 1.2,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${book.author ?? '未知'} · ${book.kind ?? '未知'} · ${book.wordCount ?? ''}',
            style: AppTextStyles.bodySm.copyWith(height: 1.35),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '最新: ${book.latestChapterTitle ?? '暫無'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodySm.copyWith(
              height: 1.35,
              color: context.warning,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          GestureDetector(
            onTap:
                sourceCount > 1
                    ? () => setState(() => _sourcesExpanded = !_sourcesExpanded)
                    : null,
            child:
                _sourcesExpanded
                    ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '來源 ($sourceCount):',
                              style: AppTextStyles.labelSm.copyWith(
                                height: 1.35,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Icon(
                              Icons.expand_less,
                              size: 16,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Wrap(
                          spacing: AppSpacing.xs,
                          runSpacing: AppSpacing.xs,
                          children:
                              widget.result.sources
                                  .map(
                                    (source) => Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: AppSpacing.sm,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.onSurfaceVariant
                                            .withValues(alpha: 0.12),
                                        borderRadius: AppRadius.cardXs,
                                      ),
                                      child: Text(
                                        source,
                                        style: AppTextStyles.labelXs.copyWith(
                                          height: 1.25,
                                          color:
                                              theme.colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                        ),
                      ],
                    )
                    : Row(
                      children: [
                        Expanded(
                          child: Text(
                            '來源: ${widget.result.sources.join(', ')}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.labelSm.copyWith(
                              height: 1.35,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        if (sourceCount > 1)
                          Icon(
                            Icons.expand_more,
                            size: 16,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                      ],
                    ),
          ),
        ],
      ),
      onTap: () {
        context.read<SearchProvider>().stopSearch();
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => BookDetailPage(searchBook: widget.result),
          ),
        );
      },
    );
  }
}
