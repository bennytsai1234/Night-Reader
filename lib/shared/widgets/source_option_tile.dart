import 'package:flutter/material.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/core/services/chinese_display.dart';

/// 換源清單的一列：書源名稱、作者與最新章節，目前書源右側打勾且不可再點。
///
/// 版面同分組清單的列（左右內距、整列高亮），可直接放進分組卡片或面板清單。
class SourceOptionTile extends StatelessWidget {
  final SearchBook searchBook;
  final bool isCurrent;
  final VoidCallback? onTap;

  const SourceOptionTile({
    super.key,
    required this.searchBook,
    this.isCurrent = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chrome = AppChrome.of(context);
    final secondaryStyle = AppTextStyles.bodySm.copyWith(
      height: 1.3,
      color: chrome.sectionText,
    );

    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppGrouped.rowTallMinHeight),
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
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    searchBook.originName ?? '未知來源',
                    style: AppTextStyles.bodyBase.copyWith(
                      height: 1.3,
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  if ((searchBook.author ?? '').isNotEmpty)
                    Text(
                      '作者: ${context.zh(searchBook.author ?? '')}',
                      style: secondaryStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  Text(
                    '最新: ${context.zh(searchBook.latestChapterTitle ?? '無最新章節資訊')}',
                    style: secondaryStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if ((searchBook.wordCount ?? '').isNotEmpty ||
                      (searchBook.kind ?? '').isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      children: [
                        if ((searchBook.wordCount ?? '').isNotEmpty)
                          _MetaChip(
                            label: searchBook.wordCount!,
                            foregroundColor: scheme.primary,
                            backgroundColor: scheme.primary.withValues(
                              alpha: 0.1,
                            ),
                          ),
                        if ((searchBook.kind ?? '').isNotEmpty)
                          _MetaChip(
                            label: searchBook.kind!,
                            foregroundColor: chrome.sectionText,
                            backgroundColor: scheme.onSurface.withValues(
                              alpha: 0.06,
                            ),
                          ),
                      ],
                    ),
                  ],
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
    );

    return Semantics(
      selected: isCurrent,
      child: InkWell(onTap: isCurrent ? null : onTap, child: row),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final String label;
  final Color foregroundColor;
  final Color backgroundColor;

  const _MetaChip({
    required this.label,
    required this.foregroundColor,
    required this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: AppRadius.pillShape,
      ),
      child: Text(
        label,
        style: AppTextStyles.micro.copyWith(
          color: foregroundColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
