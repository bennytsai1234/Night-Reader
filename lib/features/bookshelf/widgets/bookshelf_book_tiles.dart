import 'package:flutter/material.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/services/chinese_display.dart';
import 'package:night_reader/core/widgets/book_cover_widget.dart';
import 'package:night_reader/features/bookshelf/bookshelf_read_progress.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/glass_menu.dart';

/// 編輯模式的圓形勾選記號（Telegram 編輯清單左側的圓圈）。
class BookshelfCheckMark extends StatelessWidget {
  const BookshelfCheckMark({
    super.key,
    required this.selected,
    this.onCover = false,
  });

  static const double size = 22;

  final bool selected;

  /// 疊在封面上時，未選取的圓圈用紙白描邊加淡墨底，在任何封面上都看得見。
  final bool onCover;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chrome = AppChrome.of(context);
    return AnimatedContainer(
      duration: AppMotion.menu,
      curve: AppMotion.menuCurve,
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected
            ? scheme.primary
            : onCover
            ? AppPalette.ink700.withValues(alpha: 0.22)
            : Colors.transparent,
        border: Border.all(
          color: onCover
              ? AppPalette.paper50
              : selected
              ? scheme.primary
              : chrome.sectionText.withValues(alpha: 0.55),
          width: 1.5,
        ),
      ),
      child: selected
          ? Icon(Icons.check_rounded, size: 16, color: scheme.onPrimary)
          : null,
    );
  }
}

/// 書名下方的細進度線：只畫已讀比例，不顯示數字。
class BookshelfProgressLine extends StatelessWidget {
  const BookshelfProgressLine({super.key, required this.book});

  static const double height = 2;

  final Book book;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chrome = AppChrome.of(context);
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: chrome.separator.withValues(alpha: 0.5),
        borderRadius: AppRadius.pillShape,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: bookshelfReadProgress(book),
          child: Container(
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: AppRadius.pillShape,
            ),
          ),
        ),
      ),
    );
  }
}

/// 列表視圖的書：一本一張小紙卡，只放封面、書名、作者與細進度線。
/// 編輯模式時勾選圓圈從左側滑入，選取的卡片帶淡主色底。
class BookshelfListCard extends StatelessWidget {
  const BookshelfListCard({
    super.key,
    required this.book,
    this.selecting = false,
    this.selected = false,
    this.onTap,
    this.onLongPress,
    this.hero = true,
  });

  static const double coverWidth = 52;
  static const double coverHeight = 72;

  /// 編輯模式時勾選圓圈佔用的寬度（含與封面的間距）。
  static const double _checkSlot = BookshelfCheckMark.size + AppSpacing.md;

  final Book book;
  final bool selecting;
  final bool selected;
  final VoidCallback? onTap;

  /// 長按時回傳卡片在螢幕上的範圍，供情境預覽選單浮起。
  final ValueChanged<Rect>? onLongPress;

  /// 長按預覽裡的複本不能帶 Hero，否則與清單本身的 tag 重複。
  final bool hero;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chrome = AppChrome.of(context);
    final slot = selecting ? _checkSlot : 0.0;
    final name = context.zh(book.name);
    final author = context.zh(book.author).trim();

    Widget cover = BookCoverWidget(
      bookName: name,
      author: book.author,
      coverUrl: book.getDisplayCover(),
      width: coverWidth,
      height: coverHeight,
      borderRadius: AppRadius.cardXs,
    );
    if (hero) {
      cover = Hero(tag: BookCoverWidget.heroTag(book.bookUrl), child: cover);
    }

    final content = Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          AnimatedContainer(
            duration: AppMotion.menu,
            curve: AppMotion.menuCurve,
            width: slot,
            height: BookshelfCheckMark.size,
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                minWidth: _checkSlot,
                maxWidth: _checkSlot,
                child: AnimatedOpacity(
                  duration: AppMotion.menu,
                  opacity: selecting ? 1 : 0,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: BookshelfCheckMark(selected: selected),
                  ),
                ),
              ),
            ),
          ),
          cover,
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.uiMd.copyWith(
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
                if (author.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodySm.copyWith(
                      height: 1.3,
                      color: chrome.sectionText,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                BookshelfProgressLine(book: book),
              ],
            ),
          ),
        ],
      ),
    );

    final surface = chrome.groupedSurface;
    return Semantics(
      selected: selecting ? selected : null,
      child: Material(
        color: selecting && selected
            ? Color.alphaBlend(scheme.primary.withValues(alpha: 0.06), surface)
            : surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppGrouped.cardRadius,
          side: BorderSide(color: chrome.separator, width: AppGlass.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress == null
              ? null
              : () => onLongPress!(globalRectOf(context)),
          child: content,
        ),
      ),
    );
  }
}

/// 網格視圖的書籍：封面、兩行書名與細進度線；編輯模式時封面右上角
/// 顯示勾選圓圈，選取的封面微縮。
class BookshelfGridTile extends StatelessWidget {
  const BookshelfGridTile({
    super.key,
    required this.book,
    this.selecting = false,
    this.selected = false,
    this.onTap,
    this.onLongPress,
  });

  static const double coverAspectRatio = 0.72;

  final Book book;
  final bool selecting;
  final bool selected;
  final VoidCallback? onTap;

  /// 長按時回傳封面在螢幕上的範圍。
  final ValueChanged<Rect>? onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = context.zh(book.name);

    return Semantics(
      selected: selecting ? selected : null,
      child: PressScale(
        scale: 0.96,
        onTap: onTap,
        onLongPress: onLongPress == null
            ? null
            : () {
                final tile = globalRectOf(context);
                onLongPress!(
                  Rect.fromLTWH(
                    tile.left,
                    tile.top,
                    tile.width,
                    tile.width / coverAspectRatio,
                  ),
                );
              },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: coverAspectRatio,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  AnimatedScale(
                    scale: selected ? 0.92 : 1,
                    duration: AppMotion.spring,
                    curve: AppMotion.springCurve,
                    child: Hero(
                      tag: BookCoverWidget.heroTag(book.bookUrl),
                      child: BookCoverWidget(
                        bookName: name,
                        author: book.author,
                        coverUrl: book.getDisplayCover(),
                        width: double.infinity,
                        height: double.infinity,
                        borderRadius: AppRadius.cardXs,
                      ),
                    ),
                  ),
                  Positioned(
                    top: AppSpacing.sm,
                    right: AppSpacing.sm,
                    child: AnimatedOpacity(
                      duration: AppMotion.menu,
                      opacity: selecting ? 1 : 0,
                      child: BookshelfCheckMark(
                        selected: selected,
                        onCover: true,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.labelXs.copyWith(
                fontWeight: FontWeight.w600,
                height: 1.25,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            BookshelfProgressLine(book: book),
          ],
        ),
      ),
    );
  }
}

/// 編輯模式的一個工具列動作。
class BookshelfToolbarAction {
  const BookshelfToolbarAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.destructive = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool destructive;
}

/// 編輯模式的玻璃膠囊工具列，與浮動分頁列同高、佔用分頁列的位置；
/// 批次作業進行中時改顯示進度文字。
class BookshelfEditToolbar extends StatelessWidget {
  const BookshelfEditToolbar({
    super.key,
    required this.actions,
    this.progressLabel,
  });

  static const double height = AppGlass.tabBarHeight;

  final List<BookshelfToolbarAction> actions;

  /// 不為 null 時表示批次作業進行中。
  final String? progressLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final danger = Theme.of(context).brightness == Brightness.dark
        ? AppPalette.rustDark
        : AppPalette.rust;
    final busy = progressLabel != null;

    final buttons = Row(
      key: const ValueKey('buttons'),
      children: [
        for (final action in actions)
          Expanded(
            child: Semantics(
              button: true,
              enabled: action.onPressed != null,
              child: PressScale(
                onTap: action.onPressed,
                child: Opacity(
                  opacity: action.onPressed == null ? 0.38 : 1,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        action.icon,
                        size: 22,
                        color: action.destructive ? danger : scheme.onSurface,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        action.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.uiXs.copyWith(
                          color: action.destructive ? danger : scheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );

    final progress = Row(
      key: const ValueKey('progress'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox.square(
          dimension: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: scheme.primary,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Flexible(
          child: Text(
            progressLabel ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.uiSm.copyWith(color: scheme.onSurface),
          ),
        ),
      ],
    );

    return FloatingGlassToolbar(
      height: height,
      child: AnimatedSwitcher(
        duration: AppMotion.fade,
        switchInCurve: AppMotion.fadeCurve,
        switchOutCurve: AppMotion.fadeCurve,
        child: busy ? progress : buttons,
      ),
    );
  }
}
