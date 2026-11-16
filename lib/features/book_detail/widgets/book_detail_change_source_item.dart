import 'package:flutter/material.dart';
import 'package:night_reader/shared/widgets/ui_text.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/services/chinese_display.dart';
import 'package:night_reader/core/services/ui_language.dart';
import 'package:night_reader/core/utils/string_utils.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/drag_overflow_text.dart';

/// 換源清單的一列：來源名稱、作者、最新章節與字數／分類，右邊是目錄共幾章
/// （比哪個書源的目錄完整）；目前來源在名稱後面打勾且不可點。
class BookDetailChangeSourceItem extends StatelessWidget {
  const BookDetailChangeSourceItem({
    super.key,
    required this.searchBook,
    this.chapterCount,
    this.isCurrent = false,
    this.onTap,
  });

  final SearchBook searchBook;

  /// 目錄共幾章；不知道時不寫。
  final int? chapterCount;
  final bool isCurrent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final secondary = AppChrome.of(context).sectionText;
    final author = context.zh(searchBook.author ?? '').trim();
    final kind = context.zh(searchBook.kind ?? '');
    final meta = [
      if (author.isNotEmpty) author,
      context.ui(StringUtils.displayWordCount(searchBook.wordCount, kind)),
      ...StringUtils.kindLabels(kind),
    ].where((value) => value.isNotEmpty).join(' · ');
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
                      Row(
                        children: [
                          Flexible(
                            child: DragOverflowText(
                              child: UiText(
                                searchBook.originName ?? '未知來源',
                                translate: searchBook.originName == null,
                                maxLines: 1,
                                style: AppTextStyles.bodyBase.copyWith(
                                  height: 1.3,
                                  color: scheme.onSurface,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          // 勾勾跟著書源名稱，右邊只留章數：和下面清單的章數
                          // 對齊，上下比得出來。
                          if (isCurrent) ...[
                            const SizedBox(width: AppSpacing.xs),
                            Icon(
                              Icons.check_rounded,
                              size: 18,
                              color: scheme.primary,
                            ),
                          ],
                        ],
                      ),
                      if (meta.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        DragOverflowText(
                          child: UiText(
                            meta,
                            translate: false,
                            maxLines: 1,
                            style: secondaryStyle,
                          ),
                        ),
                      ],
                      const SizedBox(height: 2),
                      DragOverflowText(
                        child: UiText(
                          latestChapterLine(
                            context,
                            searchBook.latestChapterTitle,
                            fallback: '無最新章節資訊',
                          ),
                          translate: false,
                          maxLines: 1,
                          style: secondaryStyle,
                        ),
                      ),
                    ],
                  ),
                ),
                if (chapterCount case final count?) ...[
                  const SizedBox(width: AppSpacing.md),
                  UiText(
                    context.ui('共 $count 章'),
                    translate: false,
                    maxLines: 1,
                    style: AppTextStyles.bodyBase.copyWith(
                      height: 1.3,
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
