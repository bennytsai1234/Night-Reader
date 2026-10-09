import 'package:flutter/material.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/core/widgets/book_cover_widget.dart';

import '../../book_detail/book_detail_page.dart';

import 'package:night_reader/core/services/chinese_display.dart';

/// ExploreBookItem - 探索結果書籍項目
/// (對標 Android ExploreShowAdapter + item_search 佈局)
///
/// Telegram 清單列樣式：左側封面，右側書名、作者與分類、最新章節、簡介；
/// 按下整列高亮，列間分隔線從文字起點開始（[textIndent]）。
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

  static const double coverWidth = 52;
  static const double coverHeight = 70;

  /// 文字起點；平鋪清單的分隔線從這裡開始。
  static const double textIndent =
      AppGrouped.margin + coverWidth + AppSpacing.lg;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final secondary = AppChrome.of(context).sectionText;
    final kinds = _kinds(context);
    final meta = [
      if (book.author != null && book.author!.isNotEmpty)
        context.zh(book.author!),
      ...kinds,
    ].join(' · ');

    return InkWell(
      onTap: () => _navigateToDetail(context),
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
              author: context.zh(book.author ?? ''),
              width: coverWidth,
              height: coverHeight,
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
                          style: AppTextStyles.bodyBase.copyWith(
                            height: 1.3,
                            color: scheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isInBookshelf) ...[
                        const SizedBox(width: AppSpacing.sm),
                        const InfoBadge(),
                      ],
                    ],
                  ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      style: AppTextStyles.bodySm.copyWith(
                        height: 1.35,
                        color: secondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (book.latestChapterTitle != null &&
                      book.latestChapterTitle!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      '最新：${context.zh(book.latestChapterTitle!)}',
                      style: AppTextStyles.bodySm.copyWith(
                        height: 1.35,
                        color: secondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (book.intro != null && book.intro!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      context.zh(
                        book.intro!.replaceAll(RegExp(r'\s+'), ' ').trim(),
                      ),
                      style: AppTextStyles.bodySm.copyWith(
                        height: 1.4,
                        color: secondary.withValues(alpha: 0.85),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<String> _kinds(BuildContext context) {
    if (book.kind == null || book.kind!.isEmpty) return const [];
    return context
        .zh(book.kind!)
        .split(RegExp(r'[,，]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .take(3)
        .toList();
  }

  void _navigateToDetail(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BookDetailPage(
          searchBook: AggregatedSearchBook(
            book: book,
            sources: [book.originName ?? sourceName ?? '發現'],
          ),
        ),
      ),
    );
  }
}

/// 書名旁的小徽章（「書架」、書源數）；搜尋結果與發現清單共用。
class InfoBadge extends StatelessWidget {
  const InfoBadge({super.key, this.label = '書架'});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.12),
        borderRadius: AppRadius.pillShape,
      ),
      child: Text(
        label,
        style: AppTextStyles.labelXs.copyWith(
          height: 1.3,
          color: scheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
