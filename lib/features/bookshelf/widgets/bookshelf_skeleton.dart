import 'package:flutter/material.dart';
import 'package:night_reader/core/services/chinese_display.dart';
import 'package:night_reader/features/bookshelf/provider/bookshelf_provider_base.dart';
import 'package:night_reader/features/bookshelf/widgets/bookshelf_book_tiles.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';

/// 書架初次載入的骨架：依目前的網格或列表畫出同樣幾何的封面與書名佔位，
/// 書到了之後換成真的書卡時版面不跳動。放在 [Skeleton] 底下才會呼吸。
///
/// 畫 [bookCount] 本（超出畫面的不畫）；不知道有幾本時鋪滿畫面。[titles]
/// 有記下的那幾本，書名與作者的長條照真正的文字換行與寬度畫，骨架換場時
/// 每一條剛好換成那一行字；沒記下的用輪流的長度。
class BookshelfSkeleton extends StatelessWidget {
  const BookshelfSkeleton({
    super.key,
    required this.grid,
    required this.padding,
    this.bookCount,
    this.titles = const [],
  });

  final bool grid;

  /// 上次書架上的本數；null 表示不知道。
  final int? bookCount;

  /// 上次書架前面幾本的書名與作者，依當時的順序。
  final List<ShelfSkeletonTitle> titles;

  /// 與書架清單相同的內距（讓出玻璃頁首與底部浮動列）。
  final EdgeInsets padding;

  /// 與書架網格相同的欄數。
  static const int _gridColumns = 3;

  /// 書名佔位的長度，輪流使用，看起來才像不同的書。
  static const List<double> _titleWidths = [0.9, 0.65, 0.8, 0.55, 0.75];

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, constraints) =>
            grid ? _buildGrid(context, constraints) : _buildList(constraints),
      ),
    );
  }

  Widget _buildGrid(BuildContext context, BoxConstraints constraints) {
    final cellWidth =
        (constraints.maxWidth -
            padding.horizontal -
            AppSpacing.lg * (_gridColumns - 1)) /
        _gridColumns;
    final cellHeight = BookshelfGridTile.heightFor(
      cellWidth,
      MediaQuery.textScalerOf(context),
    );
    final rows = _countToFill(
      constraints.maxHeight - padding.vertical,
      cellHeight + AppSpacing.md,
    );
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: padding,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _gridColumns,
        mainAxisExtent: cellHeight,
        crossAxisSpacing: AppSpacing.lg,
        mainAxisSpacing: AppSpacing.md,
      ),
      itemCount: _limit(rows * _gridColumns),
      itemBuilder: (context, index) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AspectRatio(
            aspectRatio: BookshelfGridTile.coverAspectRatio,
            child: SkeletonBox(),
          ),
          const SizedBox(height: AppSpacing.sm),
          // 書名區與真的書卡一樣固定兩行高，進度線才落在同一個位置。
          SizedBox(
            height: BookshelfGridTile.titleHeightFor(
              MediaQuery.textScalerOf(context),
            ),
            child: Align(
              alignment: Alignment.topLeft,
              child: index < titles.length
                  ? _TextBars(
                      text: context.zh(titles[index].name),
                      style: BookshelfGridTile.titleStyle,
                      maxLines: 2,
                    )
                  : SkeletonLine(
                      style: BookshelfGridTile.titleStyle,
                      widthFactor: _titleWidths[index % _titleWidths.length],
                    ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          const _ProgressLineSkeleton(),
        ],
      ),
    );
  }

  Widget _buildList(BoxConstraints constraints) {
    const cardHeight = BookshelfListCard.coverHeight + AppSpacing.md * 2;
    final count = _countToFill(
      constraints.maxHeight - padding.vertical,
      cardHeight + AppSpacing.sm,
    );
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: padding,
      itemCount: _limit(count),
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: _ListCardSkeleton(
          titleWidth: _titleWidths[index % _titleWidths.length],
          title: index < titles.length ? titles[index] : null,
        ),
      ),
    );
  }

  /// 鋪滿畫面要 [fill] 個；知道本數時不超過本數。
  int _limit(int fill) {
    final count = bookCount;
    return count == null || count > fill ? fill : count;
  }

  static int _countToFill(double extent, double itemExtent) =>
      extent <= 0 ? 1 : (extent / itemExtent).ceil();
}

/// 列表書卡的骨架：與 [BookshelfListCard] 同樣的紙卡、封面與兩行文字位置。
class _ListCardSkeleton extends StatelessWidget {
  const _ListCardSkeleton({required this.titleWidth, this.title});

  final double titleWidth;

  /// 這一本記下的書名與作者；null 時照 [titleWidth] 畫。
  final ShelfSkeletonTitle? title;

  @override
  Widget build(BuildContext context) {
    final chrome = AppChrome.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: chrome.groupedSurface,
        borderRadius: AppGrouped.cardRadius,
        border: Border.all(color: chrome.separator, width: AppGlass.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            const SkeletonBox(
              width: BookshelfListCard.coverWidth,
              height: BookshelfListCard.coverHeight,
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title case final title?) ...[
                    _TextBars(
                      text: context.zh(title.name),
                      style: BookshelfListCard.titleStyle,
                      maxLines: 1,
                    ),
                    const SizedBox(height: 2),
                    // 沒有作者時和真的書卡一樣只留這一行的高度。
                    _TextBars(
                      text: context.zh(title.author).trim(),
                      style: BookshelfListCard.authorStyle,
                      maxLines: 1,
                    ),
                  ] else ...[
                    SkeletonLine(
                      style: BookshelfListCard.titleStyle,
                      widthFactor: titleWidth * 0.7,
                    ),
                    const SizedBox(height: 2),
                    SkeletonLine(
                      style: BookshelfListCard.authorStyle,
                      widthFactor: 0.3,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  const _ProgressLineSkeleton(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 書名下方細進度線（[BookshelfProgressLine]）的佔位，同高、撐滿寬度。
class _ProgressLineSkeleton extends StatelessWidget {
  const _ProgressLineSkeleton();

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: double.infinity,
    child: SkeletonBox(
      height: BookshelfProgressLine.height,
      borderRadius: AppRadius.pillShape,
    ),
  );
}

/// 照真正文字的換行畫出每一行的長條，每條與那一行字一樣寬；行高與真正的
/// 文字相同，所以換成文字時位置不動。空字串時只留一行的高度。
class _TextBars extends StatelessWidget {
  const _TextBars({
    required this.text,
    required this.style,
    required this.maxLines,
  });

  final String text;
  final TextStyle style;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);
    final fontSize = textScaler.scale(style.fontSize ?? 14);
    final lineExtent = fontSize * (style.height ?? 1.3);
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          // 和 Text 一樣疊在預設字型上（字族、字距），量出來才一樣寬。
          text: TextSpan(
            text: text,
            style: DefaultTextStyle.of(context).style.merge(style),
          ),
          textDirection: Directionality.of(context),
          textScaler: textScaler,
          maxLines: maxLines,
          ellipsis: '…',
        )..layout(maxWidth: constraints.maxWidth);
        final widths = [
          for (final line in painter.computeLineMetrics()) line.width,
        ];
        painter.dispose();
        if (widths.isEmpty || text.isEmpty) return SizedBox(height: lineExtent);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final width in widths)
              SizedBox(
                height: lineExtent,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SkeletonBox(width: width, height: fontSize * 0.75),
                ),
              ),
          ],
        );
      },
    );
  }
}
