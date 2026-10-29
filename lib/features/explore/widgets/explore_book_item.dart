import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/features/explore/explore_book_details.dart';
import 'package:night_reader/core/utils/string_utils.dart';
import 'package:night_reader/shared/navigation/app_page_transition.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/core/widgets/book_cover_widget.dart';
import 'package:night_reader/shared/widgets/cover_reveal.dart';
import 'package:night_reader/shared/widgets/press_ink.dart';

import '../../book_detail/book_detail_page.dart';

import 'package:night_reader/core/services/chinese_display.dart';

/// ExploreBookItem - 探索結果書籍項目
/// (對標 Android ExploreShowAdapter + item_search 佈局)
///
/// Telegram 清單列樣式：左側封面，右側書名、作者 · 字數 · 分類、最新章節，
/// 不放簡介；按下整列高亮，列間分隔線從文字起點開始（[textIndent]）。
///
/// 封面與字數可能晚一點才從書籍詳情補到（[extras]）：補到時只重建封面與
/// 作者 · 字數 · 分類那一行。封面大小固定，那一行沒有內容時也佔著一行高，
/// 換字只重排那一行，這一列與清單的版面不動。
class ExploreBookItem extends StatelessWidget {
  final SearchBook book;
  final bool isInBookshelf;
  final String? sourceName;

  /// 從書籍詳情補到的封面與字數（見 [ExploreBookDetails]）。
  final ValueListenable<ExploreBookExtras?>? extras;

  const ExploreBookItem({
    super.key,
    required this.book,
    this.isInBookshelf = false,
    this.sourceName,
    this.extras,
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
    final metaStyle = AppTextStyles.bodySm.copyWith(
      height: 1.35,
      color: secondary,
    );
    // 固定一行高（行高照字級與系統字級算）：外框的大小給死，字數補到時
    // 換字只重排這一行。
    final metaLineHeight =
        MediaQuery.textScalerOf(context).scale(metaStyle.fontSize!) *
        metaStyle.height!;

    return TransitionSource(
      child: PressInk(
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
              // 封面與右邊的字各排一塊：骨架底下一幀建一塊時
              // （[CoverReveal.paced]）分在不同幀建，一整列約 3ms，一幀放不下。
              CoverRevealSlot(
                placeholder: const SizedBox(
                  width: coverWidth,
                  height: coverHeight,
                ),
                child: _withExtras(
                  (book) => BookCoverWidget(
                    coverUrl: book.coverUrl,
                    bookName: context.zh(book.name),
                    author: context.zh(book.author ?? ''),
                    width: coverWidth,
                    height: coverHeight,
                    borderRadius: AppRadius.cardXs,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: CoverRevealSlot(
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
                      const SizedBox(height: 2),
                      SizedBox(
                        width: double.infinity,
                        height: metaLineHeight,
                        child: _withExtras(
                          (book) => Text(
                            _meta(context, book),
                            style: metaStyle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      if (book.latestChapterTitle != null &&
                          book.latestChapterTitle!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          '最新：${context.zh(book.latestChapterTitle!)}',
                          style: metaStyle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 補上 [extras] 的書；[builder] 只在補到時跟著重建。
  Widget _withExtras(Widget Function(SearchBook book) builder) {
    final extras = this.extras;
    if (extras == null) return builder(book);
    return ValueListenableBuilder<ExploreBookExtras?>(
      valueListenable: extras,
      builder: (context, value, _) =>
          builder(ExploreBookDetails.withExtras(book, value)),
    );
  }

  /// 作者 · 字數 · 分類（分類最多三個）。
  static String _meta(BuildContext context, SearchBook book) {
    final kind = context.zh(book.kind ?? '');
    final wordCount = StringUtils.displayWordCount(book.wordCount, kind);
    return [
      if (book.author != null && book.author!.isNotEmpty)
        context.zh(book.author!),
      if (wordCount.isNotEmpty) wordCount,
      if (kind.isNotEmpty) ...StringUtils.kindLabels(kind).take(3),
    ].join(' · ');
  }

  void _navigateToDetail(BuildContext context) {
    // 補到的封面與字數一起帶進書籍詳情，詳情一進頁就畫得出封面。
    final shown = ExploreBookDetails.withExtras(book, extras?.value);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BookDetailPage(
          searchBook: AggregatedSearchBook(
            book: shown,
            sources: [shown.originName ?? sourceName ?? '發現'],
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
