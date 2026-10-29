import 'package:flutter/material.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/utils/string_utils.dart';
import 'package:night_reader/shared/navigation/app_page_transition.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/core/widgets/book_cover_widget.dart';
import 'package:night_reader/shared/widgets/press_ink.dart';

import '../../book_detail/book_detail_page.dart';
import '../../explore/widgets/explore_book_item.dart';

import 'package:night_reader/core/services/chinese_display.dart';

class SearchResultItem extends StatefulWidget {
  final AggregatedSearchBook result;
  final bool isInBookshelf;

  /// 要顯示的封面；沒給時用書本身的（見 [SearchProvider.coverOf]）。
  final String? coverUrl;

  /// 進書籍詳情之前呼叫（見 [SearchProvider.rememberOpenedCard]）。
  final VoidCallback? onOpen;

  const SearchResultItem({
    super.key,
    required this.result,
    this.coverUrl,
    this.onOpen,
    this.isInBookshelf = false,
  });

  @override
  State<SearchResultItem> createState() => _SearchResultItemState();
}

typedef _ResultContent = ({
  String name,
  String? author,
  String? kind,
  String? wordCount,
  String? latestChapterTitle,
  String? coverUrl,
  bool inBookshelf,
});

class _SearchResultItemState extends State<SearchResultItem> {
  late final _content = ValueNotifier(_visibleContent());
  late final _sourceCount = ValueNotifier(widget.result.sources.length);

  _ResultContent _visibleContent() {
    final book = widget.result.book;
    return (
      name: book.name,
      author: book.author,
      kind: book.kind,
      wordCount: book.wordCount,
      latestChapterTitle: book.latestChapterTitle,
      coverUrl: widget.coverUrl ?? book.coverUrl,
      inBookshelf: widget.isInBookshelf,
    );
  }

  @override
  void didUpdateWidget(SearchResultItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    _content.value = _visibleContent();
    _sourceCount.value = widget.result.sources.length;
  }

  @override
  void dispose() {
    _content.dispose();
    _sourceCount.dispose();
    super.dispose();
  }

  void _open() {
    // 內容子樹可以沿用，但點擊永遠帶本次更新後的代表書與完整書源清單。
    final result = widget.result;
    widget.onOpen?.call();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BookDetailPage(searchBook: result),
      ),
    );
  }

  /// 每次結果發布都重算來源數，內容沒變時保留原子樹，只有標記訂閱數量。
  /// 主題與繁簡顯示仍由內容自己的 context 訂閱，不凍住外觀。
  late final Widget _view = TransitionSource(
    child: PressInk(
      onTap: _open,
      child: ValueListenableBuilder<_ResultContent>(
        valueListenable: _content,
        builder: _buildContent,
        child: ValueListenableBuilder<int>(
          valueListenable: _sourceCount,
          builder: (context, count, _) => count > 1
              ? Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.xs),
                  child: InfoBadge(label: '$count 個書源'),
                )
              : const SizedBox.shrink(),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => _view;

  Widget _buildContent(
    BuildContext context,
    _ResultContent book,
    Widget? badge,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final secondary = AppChrome.of(context).sectionText;
    final metadata = formatSearchResultMetadata(
      author: context.zh(book.author ?? ''),
      kind: context.zh(book.kind ?? ''),
      wordCount: book.wordCount,
    );
    final secondaryStyle = AppTextStyles.bodySm.copyWith(
      height: 1.35,
      color: secondary,
    );
    return Padding(
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
            width: ExploreBookItem.coverWidth,
            height: ExploreBookItem.coverHeight,
            borderRadius: AppRadius.cardXs,
          ),
          const SizedBox(width: AppSpacing.lg),
          // 書名、作者 · 字數 · 分類、最新章節各一行，上下對齊封面的上下
          // 緣，每一列一樣高；字放大到超過封面高時才撐高。
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: ExploreBookItem.coverHeight,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          context.zh(book.name),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodyBase.copyWith(
                            height: 1.3,
                            color: scheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (book.inBookshelf) ...[
                        const SizedBox(width: AppSpacing.sm),
                        const InfoBadge(),
                      ],
                      ?badge,
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
          ),
        ],
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
