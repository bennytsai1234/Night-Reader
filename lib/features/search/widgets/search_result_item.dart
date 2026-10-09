import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/core/widgets/book_cover_widget.dart';

import '../search_provider.dart';
import '../../book_detail/book_detail_page.dart';
import '../../explore/widgets/explore_book_item.dart';

import 'package:night_reader/core/services/chinese_display.dart';

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
    final scheme = Theme.of(context).colorScheme;
    final secondary = AppChrome.of(context).sectionText;
    final metadata = formatSearchResultMetadata(
      author: context.zh(book.author),
      kind: context.zh(book.kind ?? ''),
      wordCount: book.wordCount,
    );
    final secondaryStyle = AppTextStyles.bodySm.copyWith(
      height: 1.35,
      color: secondary,
    );
    return InkWell(
      onTap: () {
        // 搜尋在背景繼續，回來時結果已經補齊。
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => BookDetailPage(searchBook: widget.result),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppGrouped.margin,
          AppSpacing.md,
          AppGrouped.margin,
          AppSpacing.md,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BookCoverWidget(
              coverUrl: book.coverUrl,
              bookName: context.zh(book.name),
              author: context.zh(book.author),
              width: ExploreBookItem.coverWidth,
              height: ExploreBookItem.coverHeight,
              borderRadius: AppRadius.cardXs,
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          context.zh(book.name),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodyBase.copyWith(
                            height: 1.3,
                            color: scheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (widget.isInBookshelf) ...[
                        const SizedBox(width: AppSpacing.sm),
                        const InfoBadge(),
                      ],
                      if (sourceCount > 1) ...[
                        const SizedBox(width: AppSpacing.xs),
                        InfoBadge(label: '$sourceCount 個書源'),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    metadata,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: secondaryStyle,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '最新：${context.zh(_valueOrFallback(book.latestChapterTitle, '暫無'))}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: secondaryStyle,
                  ),
                  const SizedBox(height: 2),
                  _buildSources(context, sourceCount, secondary),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSources(BuildContext context, int sourceCount, Color color) {
    final style = AppTextStyles.labelSm.copyWith(height: 1.35, color: color);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: sourceCount > 1
          ? () => setState(() => _sourcesExpanded = !_sourcesExpanded)
          : null,
      child: AnimatedSize(
        duration: AppMotion.menu,
        curve: AppMotion.menuCurve,
        alignment: Alignment.topLeft,
        child: _sourcesExpanded
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('來源（$sourceCount）', style: style),
                      Icon(Icons.expand_less_rounded, size: 16, color: color),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      for (final source in widget.result.sources)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: AppRadius.pillShape,
                          ),
                          child: Text(
                            source,
                            style: AppTextStyles.labelXs.copyWith(
                              height: 1.25,
                              color: color,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              )
            : Row(
                children: [
                  Expanded(
                    child: Text(
                      '來源：${widget.result.sources.join('、')}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: style,
                    ),
                  ),
                  if (sourceCount > 1)
                    Icon(Icons.expand_more_rounded, size: 16, color: color),
                ],
              ),
      ),
    );
  }
}

String formatSearchResultMetadata({
  String? author,
  String? kind,
  String? wordCount,
}) {
  final values = <String>[
    if ((author ?? '').trim().isNotEmpty) author!.trim(),
    if ((kind ?? '').trim().isNotEmpty) kind!.trim(),
    if ((wordCount ?? '').trim().isNotEmpty) wordCount!.trim(),
  ];
  return values.isEmpty ? '資訊未提供' : values.join(' · ');
}

String _valueOrFallback(String? value, String fallback) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? fallback : trimmed;
}
