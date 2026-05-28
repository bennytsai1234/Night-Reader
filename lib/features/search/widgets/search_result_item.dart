import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:reader/core/models/search_book.dart';
import 'package:reader/shared/theme/app_tokens.dart';
import 'package:reader/shared/theme/app_text_styles.dart';
import 'package:reader/core/widgets/book_cover_widget.dart';
import 'package:reader/shared/theme/context_ext.dart';
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
    return ListTile(
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
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          if (widget.isInBookshelf) ...[
            Container(
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: AppRadius.cardMd,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.library_add_check,
                    size: 12,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '書架',
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (sourceCount > 1)
            Container(
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: AppRadius.cardMd,
              ),
              child: Text(
                '$sourceCount 源',
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          Text(
            '${book.author ?? '未知'} · ${book.kind ?? '未知'} · ${book.wordCount ?? ''}',
            style: AppTextStyles.bodyXs,
          ),
          const SizedBox(height: 2),
          Text(
            '最新: ${book.latestChapterTitle ?? '暫無'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.labelSm.copyWith(color: context.warning),
          ),
          const SizedBox(height: 2),
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
                              style: AppTextStyles.labelXs.copyWith(
                                color:
                                    Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.expand_less,
                              size: 14,
                              color:
                                  Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Wrap(
                          spacing: 4,
                          runSpacing: 2,
                          children:
                              widget.result.sources
                                  .map(
                                    (s) => Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant
                                            .withValues(alpha: 0.12),
                                        borderRadius: AppRadius.cardXs,
                                      ),
                                      child: Text(
                                        s,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color:
                                              Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
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
                            style: AppTextStyles.labelXs.copyWith(
                              color:
                                  Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        if (sourceCount > 1)
                          Icon(
                            Icons.expand_more,
                            size: 14,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
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
