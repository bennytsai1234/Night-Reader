import 'package:flutter/material.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/utils/string_utils.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/core/widgets/book_cover_widget.dart';

import '../../book_detail/book_detail_page.dart';
import '../../explore/widgets/explore_book_item.dart';

import 'package:night_reader/core/services/chinese_display.dart';

class SearchResultItem extends StatelessWidget {
  final AggregatedSearchBook result;
  final bool isInBookshelf;

  const SearchResultItem({
    super.key,
    required this.result,
    this.isInBookshelf = false,
  });

  @override
  Widget build(BuildContext context) {
    final book = result.book;
    final sourceCount = result.sources.length;
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
        // 詳情蓋住搜尋頁時，還沒送出的書源先暫停，回來再接著搜。
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => BookDetailPage(searchBook: result),
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
                      if (isInBookshelf) ...[
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 作者 · 字數 · 分類。字數排在分類前面，分類很長被截掉時字數還看得到；
/// 字數統一寫法、分類丟掉混進來的日期與數字，見 [StringUtils]。
String formatSearchResultMetadata({
  String? author,
  String? kind,
  String? wordCount,
}) {
  final values = <String>[
    if ((author ?? '').trim().isNotEmpty) author!.trim(),
    StringUtils.displayWordCount(wordCount, kind),
    ...StringUtils.kindLabels(kind),
  ]..removeWhere((value) => value.isEmpty);
  return values.isEmpty ? '資訊未提供' : values.join(' · ');
}

String _valueOrFallback(String? value, String fallback) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? fallback : trimmed;
}
