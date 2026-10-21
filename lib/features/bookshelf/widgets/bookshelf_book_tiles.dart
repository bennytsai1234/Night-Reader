import 'package:flutter/material.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/services/book_update_service.dart';
import 'package:night_reader/core/services/chinese_display.dart';
import 'package:night_reader/core/widgets/book_cover_widget.dart';
import 'package:night_reader/core/widgets/default_book_cover.dart';
import 'package:night_reader/features/bookshelf/bookshelf_read_progress.dart';
import 'package:night_reader/shared/navigation/app_page_transition.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/glass_menu.dart';

/// 書卡上選取（勾號、圓圈、讓位、卡片底色）與角標的動畫時長：系統關閉動畫
/// 時一律為 0，這組同步的動畫一起直接到位。
Duration _motion(BuildContext context, Duration duration) =>
    MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;

/// 系統關閉動畫的設定一改，整張書卡重新建立：正在播的選取與角標動畫直接
/// 停在終點，不播完剩下那段。
Widget _landOnMotionChange(BuildContext context, Widget child) => KeyedSubtree(
  key: ValueKey(('motion', MediaQuery.disableAnimationsOf(context))),
  child: child,
);

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
    final duration = _motion(context, AppMotion.menu);
    return AnimatedContainer(
      duration: duration,
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
      // 勾號和圓圈的填色一起淡入淡出，不在第一幀就整個冒出來。
      child: AnimatedOpacity(
        duration: duration,
        curve: AppMotion.menuCurve,
        opacity: selected ? 1 : 0,
        child: Icon(Icons.check_rounded, size: 16, color: scheme.onPrimary),
      ),
    );
  }
}

/// 書架檢查後封面右上角的結果：有新章節是淺綠小膠囊「+N」，檢查失敗是
/// 淺紅小圓「!」。結果清掉時淡出。
///
/// 兩色取現有色票裡的淺綠 [AppPalette.mossDark] 與淺紅
/// [AppPalette.rustDark]，淺色與深色模式共用，配墨色字（8.6:1、7.3:1）。
/// 封面可能很淺，所以加一圈淡墨髮絲線分出邊緣。
class BookshelfUpdateBadge extends StatelessWidget {
  const BookshelfUpdateBadge({super.key, required this.result});

  static const double height = 16;
  static const Color newChaptersColor = AppPalette.mossDark;
  static const Color failedColor = AppPalette.rustDark;
  static const Color _textColor = AppPalette.ink700;

  final BookUpdateCheckResult? result;

  static final Border _edge = Border.all(
    color: AppPalette.ink700.withValues(alpha: 0.25),
    width: 0.5,
  );

  @override
  Widget build(BuildContext context) {
    final result = this.result;
    // 角標出現與清掉時整塊淡入淡出；換成另一個結果（「+12」→「+3」、
    // 「+3」→「!」）時同一塊膠囊留著，寬度與底色跟著淡換連續變化。
    return AnimatedSwitcher(
      duration: _motion(context, AppMotion.fade),
      switchInCurve: AppMotion.fadeCurve,
      switchOutCurve: AppMotion.fadeCurve,
      child: result == null
          ? const SizedBox.shrink(key: ValueKey('no-badge'))
          : _BadgePill(key: const ValueKey('badge'), result: result),
    );
  }
}

/// 角標膠囊：失敗的「!」是同高的正圓，也就是最窄的膠囊，所以兩種結果
/// 共用一塊，換結果時寬度、底色與字都在 [AppMotion.fade] 內連續換過去，
/// 淡換結束時不會再縮一下、整塊往右跳。
class _BadgePill extends StatelessWidget {
  const _BadgePill({super.key, required this.result});

  final BookUpdateCheckResult result;

  @override
  Widget build(BuildContext context) {
    final failed = result.failed;
    final count = result.newChapterCount;
    final style = AppTextStyles.micro.copyWith(
      height: 1,
      fontWeight: failed ? FontWeight.w700 : FontWeight.w600,
      color: BookshelfUpdateBadge._textColor,
    );
    final label = Text(
      failed ? '!' : '+$count',
      key: ValueKey(failed ? 'failed' : 'new-$count'),
      style: style,
    );
    // 系統關閉動畫時字、大小與底色一起直接換好。AnimatedSize 時長為 0 時
    // 會在排版中途重設自己，不能只把時長設成 0，直接拿掉。
    final animate = !MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: failed ? '檢查更新失敗' : '有 $count 個新章節',
      child: ExcludeSemantics(
        child: AnimatedContainer(
          duration: animate ? AppMotion.fade : Duration.zero,
          curve: AppMotion.fadeCurve,
          height: BookshelfUpdateBadge.height,
          constraints: const BoxConstraints(
            minWidth: BookshelfUpdateBadge.height,
          ),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: failed
                ? BookshelfUpdateBadge.failedColor
                : BookshelfUpdateBadge.newChaptersColor,
            borderRadius: AppRadius.pillShape,
            border: BookshelfUpdateBadge._edge,
          ),
          child: !animate
              ? label
              : AnimatedSize(
                  duration: AppMotion.fade,
                  curve: AppMotion.fadeCurve,
                  child: AnimatedSwitcher(
                    duration: AppMotion.fade,
                    switchInCurve: AppMotion.fadeCurve,
                    switchOutCurve: AppMotion.fadeCurve,
                    // 大小只照新的字量：舊字縮成 0×0 的錨點、從中央溢出畫，
                    // 外面的 AnimatedSize 一開始淡換就往新寬度走。預設的排法取
                    // 新舊之中較大者，舊字淡完那一刻才縮，角標會跳一下。
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: [
                        for (final child in previous)
                          SizedBox.shrink(
                            child: OverflowBox(
                              maxWidth: double.infinity,
                              maxHeight: double.infinity,
                              child: child,
                            ),
                          ),
                        ?current,
                      ],
                    ),
                    child: label,
                  ),
                ),
        ),
      ),
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
/// 編輯模式時封面往右讓出位置、勾選圓圈在讓出的位置淡入（各做一件事，
/// ADR 0022），選取的卡片帶淡主色底。
class BookshelfListCard extends StatelessWidget {
  const BookshelfListCard({
    super.key,
    required this.book,
    this.selecting = false,
    this.selected = false,
    this.onTap,
    this.onLongPress,
    this.updateBadge,
  });

  static const double coverWidth = 52;
  static const double coverHeight = 72;

  /// 書名與作者的字型；載入骨架照它們量出每一行的寬度。
  static final TextStyle titleStyle = AppTextStyles.uiMd.copyWith(
    height: 1.3,
    fontWeight: FontWeight.w600,
  );
  static final TextStyle authorStyle = AppTextStyles.bodySm.copyWith(
    height: 1.3,
  );

  /// 編輯模式時勾選圓圈佔用的寬度（含與封面的間距）。
  static const double _checkSlot = BookshelfCheckMark.size + AppSpacing.md;

  final Book book;
  final bool selecting;
  final bool selected;
  final VoidCallback? onTap;

  /// 長按時回傳卡片在螢幕上的範圍，供情境預覽選單浮起。
  final ValueChanged<Rect>? onLongPress;

  /// 書架檢查後暫時顯示在封面右上角的結果。
  final BookUpdateCheckResult? updateBadge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chrome = AppChrome.of(context);
    final slot = selecting ? _checkSlot : 0.0;
    final name = context.zh(book.name);
    final author = context.zh(book.author).trim();

    Widget cover = ValueListenableBuilder<bool>(
      valueListenable: UnifiedCovers.enabled,
      builder: (context, _, _) => BookCoverWidget(
        bookName: name,
        author: book.author,
        coverUrl: UnifiedCovers.coverOf(book),
        width: coverWidth,
        height: coverHeight,
        borderRadius: AppRadius.cardXs,
      ),
    );
    cover = Stack(
      clipBehavior: Clip.none,
      children: [
        cover,
        Positioned(
          top: -AppSpacing.xs,
          right: -AppSpacing.xs,
          child: BookshelfUpdateBadge(result: updateBadge),
        ),
      ],
    );

    final content = Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          // 圓圈的濃淡由此刻讓出的寬度決定：寬度不到圓圈本身（22）時完全
          // 透明，讓滿（34）時不透明，不會被邊緣削一半像在滑動。進場途中
          // 退出也從當下的寬度接著收，不另跑一條淡入淡出。
          AnimatedContainer(
            duration: _motion(context, AppMotion.menu),
            curve: AppMotion.menuCurve,
            width: slot,
            height: BookshelfCheckMark.size,
            child: ClipRect(
              child: LayoutBuilder(
                builder: (context, constraints) => OverflowBox(
                  alignment: Alignment.centerLeft,
                  minWidth: _checkSlot,
                  maxWidth: _checkSlot,
                  child: Opacity(
                    opacity:
                        ((constraints.maxWidth - BookshelfCheckMark.size) /
                                (_checkSlot - BookshelfCheckMark.size))
                            .clamp(0.0, 1.0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: BookshelfCheckMark(selected: selected),
                    ),
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
                  style: titleStyle.copyWith(color: scheme.onSurface),
                ),
                // 沒有作者也留著這一行的高度：每張卡的文字位置一樣，
                // 載入骨架（不知道哪本沒有作者）才對得上。
                const SizedBox(height: 2),
                Text(
                  author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: authorStyle.copyWith(color: chrome.sectionText),
                ),
                const SizedBox(height: AppSpacing.md),
                BookshelfProgressLine(book: book),
              ],
            ),
          ),
        ],
      ),
    );

    final surface = chrome.groupedSurface;
    final card = Semantics(
      selected: selecting ? selected : null,
      child: TransitionSource(
        radius: AppGrouped.radius,
        // 選取的淡主色底與勾選圓圈的填色同時、同速漸變（Material 不會自己
        // 漸變底色）。漸變的是主色的濃淡、不是兩個顏色之間：換深淺或風格
        // 時底色直接換成新配色，不另外慢慢過渡。
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: selecting && selected ? 1 : 0),
          duration: _motion(context, AppMotion.menu),
          curve: AppMotion.menuCurve,
          builder: (context, tint, child) => Material(
            color: tint == 0
                ? surface
                : Color.alphaBlend(
                    scheme.primary.withValues(alpha: 0.06 * tint),
                    surface,
                  ),
            shape: const RoundedRectangleBorder(
              borderRadius: AppGrouped.cardRadius,
            ),
            clipBehavior: Clip.antiAlias,
            child: child,
          ),
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress == null
                ? null
                : () => onLongPress!(globalRectOf(context)),
            child: content,
          ),
        ),
      ),
    );
    return _landOnMotionChange(context, card);
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
    this.updateBadge,
  });

  static const double coverAspectRatio = 0.72;

  /// 書名字級與行高，[heightFor] 依此推算兩行書名佔的高度。
  static const double _titleFontSize = 11;
  static const double _titleLineHeight = 1.25;
  static final TextStyle titleStyle = AppTextStyles.labelXs.copyWith(
    fontSize: _titleFontSize,
    fontWeight: FontWeight.w600,
    height: _titleLineHeight,
  );

  /// 一格的實際高度：封面、兩行書名（跟著系統字級放大）與進度線，
  /// 網格據此決定列高，字級放大時才不會溢出。
  static double heightFor(double width, TextScaler textScaler) {
    return width / coverAspectRatio +
        AppSpacing.sm * 2 +
        titleHeightFor(textScaler) +
        BookshelfProgressLine.height +
        1; // 字形度量取整的餘裕。
  }

  /// 書名區固定兩行高：一行的書名下方留白，同一列的進度線才對齊。
  static double titleHeightFor(TextScaler textScaler) =>
      textScaler.scale(_titleFontSize) * _titleLineHeight * 2;

  final Book book;
  final bool selecting;
  final bool selected;
  final VoidCallback? onTap;

  /// 長按時回傳封面在螢幕上的範圍。
  final ValueChanged<Rect>? onLongPress;

  /// 書架檢查後暫時顯示在封面右上角的結果；編輯模式時讓位給勾選圓圈。
  final BookUpdateCheckResult? updateBadge;

  /// 整格（封面在上、書名在下）裡封面的範圍。
  static Rect _coverOf(Rect tile) => Rect.fromLTWH(
    tile.left,
    tile.top,
    tile.width,
    tile.width / coverAspectRatio,
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = context.zh(book.name);

    final tile = Semantics(
      selected: selecting ? selected : null,
      child: PressScale(
        scale: 0.96,
        onTap: onTap,
        onLongPress: onLongPress == null
            ? null
            : () => onLongPress!(_coverOf(globalRectOf(context))),
        // 點封面或書名都從封面長出來。
        child: TransitionSource(
          radius: AppRadius.xs,
          area: _coverOf,
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
                      duration: _motion(context, AppMotion.spring),
                      curve: AppMotion.springCurve,
                      child: ValueListenableBuilder<bool>(
                        valueListenable: UnifiedCovers.enabled,
                        builder: (context, _, _) => BookCoverWidget(
                          bookName: name,
                          author: book.author,
                          coverUrl: UnifiedCovers.coverOf(book),
                          width: double.infinity,
                          height: double.infinity,
                          borderRadius: AppRadius.cardXs,
                        ),
                      ),
                    ),
                    Positioned(
                      top: AppSpacing.xs,
                      right: AppSpacing.xs,
                      child: BookshelfUpdateBadge(
                        result: selecting ? null : updateBadge,
                      ),
                    ),
                    Positioned(
                      top: AppSpacing.sm,
                      right: AppSpacing.sm,
                      child: AnimatedOpacity(
                        duration: _motion(context, AppMotion.menu),
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
              SizedBox(
                height: titleHeightFor(MediaQuery.textScalerOf(context)),
                child: Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: titleStyle.copyWith(color: scheme.onSurface),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              BookshelfProgressLine(book: book),
            ],
          ),
        ),
      ),
    );
    return _landOnMotionChange(context, tile);
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
        duration: _motion(context, AppMotion.fade),
        switchInCurve: AppMotion.fadeCurve,
        switchOutCurve: AppMotion.fadeCurve,
        child: busy ? progress : buttons,
      ),
    );
  }
}
