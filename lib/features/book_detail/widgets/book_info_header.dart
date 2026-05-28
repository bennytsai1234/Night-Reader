import 'package:flutter/material.dart';
import 'package:reader/core/models/book.dart';
import 'package:reader/core/models/chapter.dart';
import 'package:reader/core/widgets/book_cover_widget.dart';
import 'package:reader/features/reader_v2/runtime/reader_v2_open_target.dart';
import 'package:reader/shared/theme/app_text_styles.dart';
import 'package:reader/shared/theme/app_tokens.dart';
import 'package:reader/shared/theme/context_ext.dart';
import '../book_detail_provider.dart';

class BookInfoHeader extends StatelessWidget {
  final Book book;
  final BookDetailProvider provider;
  final Function(BuildContext, String) showPhotoView;
  final VoidCallback onEdit;
  final Function(BuildContext, Book) showSourceOptions;
  final void Function(BuildContext, Book, ReaderV2OpenTarget, List<BookChapter>)
  navigateToReader;
  final Function(BuildContext, BookDetailProvider) showChangeSource;
  final Future<void> Function(BuildContext, BookDetailProvider) toggleBookshelf;

  const BookInfoHeader({
    super.key,
    required this.book,
    required this.provider,
    required this.showPhotoView,
    required this.onEdit,
    required this.showSourceOptions,
    required this.navigateToReader,
    required this.showChangeSource,
    required this.toggleBookshelf,
  });

  @override
  Widget build(BuildContext context) {
    final coverUrl = book.getDisplayCover();
    final actionButtonStyle = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size.fromHeight(44)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
      ),
      textStyle: WidgetStatePropertyAll(
        Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: AppRadius.cardMd),
      ),
    );
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onLongPress: () {
              if (coverUrl != null && coverUrl.isNotEmpty) {
                showPhotoView(context, coverUrl);
              }
            },
            child: Hero(
              tag: 'book_cover',
              child: BookCoverWidget(
                coverUrl: coverUrl,
                bookName: book.name,
                author: book.author,
                width: 100,
                height: 140,
                borderRadius: AppRadius.cardXs,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: GestureDetector(
              onTap: onEdit,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(book.name, style: AppTextStyles.titleMd),
                  const SizedBox(height: 8),
                  Text('作者：${book.author}', style: AppTextStyles.bodyMd),
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: () => showSourceOptions(context, book),
                    child: Text(
                      '來源：${book.originName}',
                      style: AppTextStyles.bodySm.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _SourceStatusChip(provider: provider),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed:
                              () => navigateToReader(
                                context,
                                book,
                                ReaderV2OpenTarget.resume(book),
                                provider.allChapters,
                              ),
                          style: actionButtonStyle,
                          icon: const Icon(Icons.menu_book_rounded, size: 18),
                          label: Text(
                            book.chapterIndex == 0 && book.charOffset == 0
                                ? '開始閱讀'
                                : '繼續閱讀',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => toggleBookshelf(context, provider),
                          style: actionButtonStyle,
                          icon: Icon(
                            provider.isInBookshelf
                                ? Icons.library_add_check
                                : Icons.library_add,
                            size: 18,
                          ),
                          label: Text(provider.isInBookshelf ? '移出書架' : '放入書架'),
                        ),
                      ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 4,
                      children: [
                        TextButton(
                          onPressed: () => showChangeSource(context, provider),
                          child: const Text('換源', style: AppTextStyles.labelSm),
                        ),
                      ],
                    ),
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

class _SourceStatusChip extends StatelessWidget {
  const _SourceStatusChip({required this.provider});

  final BookDetailProvider provider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final healthy = provider.sourceStatusIsHealthy;
    final color = healthy ? context.success : context.warning;
    final foreground = healthy ? context.success : context.warning;
    return Tooltip(
      message: provider.sourceStatusDescription,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: AppRadius.pillShape,
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Text(
          provider.sourceStatusLabel,
          style: theme.textTheme.labelSmall?.copyWith(
            color: foreground,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
