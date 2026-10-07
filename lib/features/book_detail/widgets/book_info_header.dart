import 'package:flutter/material.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_reading_state.dart';
import 'package:night_reader/core/widgets/book_cover_widget.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/glass.dart';

import '../book_detail_provider.dart';
import 'package:night_reader/core/services/chinese_display.dart';

/// Telegram 個人資料頁式的書籍頁首：置中封面、書名與作者，下方一排圓角
/// 玻璃動作按鈕（圖示在上、小字在下）。
///
/// 頁面往上捲時這一區捲進玻璃頁首底下，由頁首標題接手顯示書名
/// （見 [collapseOffset]）。
class BookInfoHeader extends StatelessWidget {
  final Book book;
  final BookDetailProvider provider;
  final void Function(BuildContext context, String url, String heroTag)
  showPhotoView;
  final VoidCallback onRead;
  final VoidCallback onToggleBookshelf;

  /// 本機書沒有換源，傳 null 隱藏按鈕。
  final VoidCallback? onChangeSource;
  final VoidCallback onShowToc;

  const BookInfoHeader({
    super.key,
    required this.book,
    required this.provider,
    required this.showPhotoView,
    required this.onRead,
    required this.onToggleBookshelf,
    required this.onChangeSource,
    required this.onShowToc,
  });

  static const double coverWidth = 108;
  static const double coverHeight = 152;
  static const double _topGap = AppSpacing.sm;

  /// 書名第一行捲進頁首底下時的捲動位移；超過後頁首標題淡入。
  static const double collapseOffset =
      _topGap + coverHeight + AppSpacing.lg + 24;

  @override
  Widget build(BuildContext context) {
    final coverUrl = book.getDisplayCover();
    final scheme = Theme.of(context).colorScheme;
    final chrome = AppChrome.of(context);
    final author = context.zh(book.author).trim();

    return Column(
      children: [
        const SizedBox(height: _topGap),
        GestureDetector(
          onLongPress: () {
            if (coverUrl != null && coverUrl.isNotEmpty) {
              showPhotoView(
                context,
                coverUrl,
                BookCoverWidget.heroTag(book.bookUrl),
              );
            }
          },
          child: Hero(
            tag: BookCoverWidget.heroTag(book.bookUrl),
            child: BookCoverWidget(
              coverUrl: coverUrl,
              bookName: context.zh(book.name),
              author: author,
              width: coverWidth,
              height: coverHeight,
              borderRadius: AppRadius.cardXs,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
          child: Text(
            context.zh(book.name),
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.titleXl.copyWith(color: scheme.onSurface),
          ),
        ),
        if (author.isNotEmpty) ...[
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
            child: Text(
              author,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodyBase.copyWith(color: chrome.sectionText),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppGrouped.margin),
          child: Row(
            children: [
              for (final (i, button) in [
                _ActionButton(
                  icon: Icons.menu_book_rounded,
                  label: book.hasStartedReading ? '繼續閱讀' : '開始閱讀',
                  onTap: onRead,
                ),
                _ActionButton(
                  icon:
                      provider.isInBookshelf
                          ? Icons.library_add_check_rounded
                          : Icons.library_add_outlined,
                  label: provider.isInBookshelf ? '已在書架' : '加入書架',
                  tooltip: provider.isInBookshelf ? '移出書架' : '加入書架',
                  onTap: onToggleBookshelf,
                ),
                if (onChangeSource != null)
                  _ActionButton(
                    icon: Icons.swap_horiz_rounded,
                    label: '換源',
                    onTap: onChangeSource!,
                  ),
                _ActionButton(
                  icon: Icons.format_list_bulleted_rounded,
                  label: '目錄',
                  onTap: onShowToc,
                ),
              ].indexed) ...[
                if (i > 0) const SizedBox(width: AppSpacing.sm),
                Expanded(child: button),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// 頁首動作按鈕：圓角玻璃塊，圖示在上、小字在下（Telegram 個人頁按鈕）。
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? tooltip;

  static const double _height = 58;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    Widget button = Semantics(
      button: true,
      label: tooltip ?? label,
      excludeSemantics: true,
      child: PressScale(
        scale: 0.95,
        onTap: onTap,
        child: SizedBox(
          height: _height,
          child: GlassSurface(
            borderRadius: AppRadius.cardMd,
            shadow: false,
            blur: false,
            tint: AppChrome.of(context).groupedSurface,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 22, color: color),
                const SizedBox(height: 3),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                  ),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.uiXs.copyWith(color: color),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (tooltip != null && tooltip != label) {
      button = Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}

/// 書源狀態小標籤（正常／異常），放在「來源」列右側。
class SourceStatusChip extends StatelessWidget {
  const SourceStatusChip({super.key, required this.provider});

  final BookDetailProvider provider;

  @override
  Widget build(BuildContext context) {
    final healthy = provider.sourceStatusIsHealthy;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color =
        healthy
            ? (dark ? AppPalette.mossDark : AppPalette.moss)
            : (dark ? AppPalette.teaDark : AppPalette.tea);
    return Tooltip(
      message: provider.sourceStatusDescription,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 2,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: AppRadius.pillShape,
        ),
        child: Text(
          provider.sourceStatusLabel,
          style: AppTextStyles.labelXs.copyWith(
            height: 1.3,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
