import 'package:flutter/material.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/services/chinese_display.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';

/// 換源清單的一列：來源名稱、作者、最新章節與字數／分類；目前來源右側打勾
/// 且不可點。
class BookDetailChangeSourceItem extends StatelessWidget {
  const BookDetailChangeSourceItem({
    super.key,
    required this.searchBook,
    this.isCurrent = false,
    this.onTap,
  });

  final SearchBook searchBook;
  final bool isCurrent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final secondary = AppChrome.of(context).sectionText;
    final author = context.zh(searchBook.author ?? '').trim();
    final meta = [
      if (author.isNotEmpty) author,
      if ((searchBook.wordCount ?? '').isNotEmpty) searchBook.wordCount!,
      if ((searchBook.kind ?? '').isNotEmpty) searchBook.kind!,
    ].join(' · ');
    final secondaryStyle = AppTextStyles.bodySm.copyWith(
      height: 1.35,
      color: secondary,
    );

    return Semantics(
      selected: isCurrent,
      child: InkWell(
        onTap: isCurrent ? null : onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AppGrouped.rowTallMinHeight,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppGrouped.rowPadding,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        searchBook.originName ?? '未知來源',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodyBase.copyWith(
                          height: 1.3,
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (meta.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: secondaryStyle,
                        ),
                      ],
                      const SizedBox(height: 2),
                      Text(
                        '最新：${context.zh(searchBook.latestChapterTitle ?? '無最新章節資訊')}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: secondaryStyle,
                      ),
                    ],
                  ),
                ),
                if (isCurrent) ...[
                  const SizedBox(width: AppSpacing.md),
                  Icon(Icons.check_rounded, size: 22, color: scheme.primary),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
