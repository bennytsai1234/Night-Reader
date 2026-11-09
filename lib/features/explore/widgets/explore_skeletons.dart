import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/services/chinese_display.dart';
import 'package:night_reader/shared/layout/readable_width.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:night_reader/shared/widgets/grouped_list_skeleton.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';

import 'explore_book_item.dart';

/// 佔位文字條的長度，輪流使用，看起來才像不同的內容。
const List<double> _widths = [0.45, 0.6, 0.35, 0.55, 0.4, 0.5];

/// 發現頁書源清單的骨架：一張分組卡片，每列一條書源名稱。
class ExploreSourceListSkeleton extends StatelessWidget {
  const ExploreSourceListSkeleton({
    super.key,
    required this.padding,
    this.count,
    this.names = const [],
  });

  /// 與書源清單相同的內距。
  final EdgeInsets padding;

  /// 尚未讀取時的上次列數；null 才需要鋪滿畫面。
  final int? count;

  /// 這輪資料回來後，可用真正名稱而不是固定比例重算最後一幀的骨架。
  final List<String> names;

  @override
  Widget build(BuildContext context) {
    final rowHeight = math.max(
      AppGrouped.rowMinHeight,
      MediaQuery.textScalerOf(context).scale(AppTextStyles.bodyBase.fontSize!) *
              1.3 +
          AppSpacing.md * 2,
    );
    return ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fill = _countToFill(constraints, padding, rowHeight);
          final rows = count == null ? fill : count!.clamp(0, fill);
          final cardCount = count == null || count! > fill ? rows + 1 : rows;
          return ListView.builder(
            // 骨架呼吸時整片每一幀都重畫，每列各一層只多了每一幀的開銷。
            addRepaintBoundaries: false,
            physics: const NeverScrollableScrollPhysics(),
            padding: padding,
            itemCount: rows,
            itemBuilder: (context, index) => GroupedSliceItem(
              index: index,
              count: cardCount,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: AppGrouped.rowMinHeight,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppGrouped.rowPadding,
                    vertical: AppSpacing.md,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: index < names.length
                            ? LayoutBuilder(
                                builder: (context, constraints) {
                                  final text = GroupedItemShape.text(
                                    context,
                                    names[index],
                                    style: AppTextStyles.bodyBase.copyWith(
                                      height: 1.3,
                                    ),
                                    width: constraints.maxWidth,
                                    maxLines: 1,
                                  );
                                  return SkeletonShapes(
                                    height: text.height,
                                    shapes: (_) => text.marks,
                                  );
                                },
                              )
                            : SkeletonLine(
                                style: AppTextStyles.bodyBase.copyWith(
                                  height: 1.3,
                                ),
                                widthFactor: _widths[index % _widths.length],
                              ),
                      ),
                      // 真正的發現書源列右側永遠有一個 22×22 展開箭頭。
                      const SkeletonBox(
                        width: 22,
                        height: 22,
                        borderRadius: BorderRadius.all(Radius.circular(5.5)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 發現分類書單的骨架：與 [ExploreBookItem] 同樣的封面與文字位置。
class ExploreBookListSkeleton extends StatelessWidget {
  const ExploreBookListSkeleton({
    super.key,
    required this.padding,
    this.books = const [],
    this.inBookshelf,
  });

  /// 與書單相同的內距。
  final EdgeInsets padding;

  /// 取得分類書單後，使用本輪真正的書名、作者與最新章節排骨架。
  final List<SearchBook> books;
  final bool Function(SearchBook book)? inBookshelf;

  /// 和 [ExploreBookItem] 同一個橫向空間、字級與條件：書名最多兩行，
  /// 作者等資料固定一行，最新章節存在時才多一行。
  /// 真正的列若高於封面，內容分幀建立前的佔位必須跟著長高。
  static double rowHeightFor(
    BuildContext context,
    SearchBook book, {
    bool isInBookshelf = false,
  }) {
    final titleStyle = AppTextStyles.bodyBase.copyWith(
      height: 1.3,
      fontWeight: FontWeight.w600,
    );
    final metaStyle = AppTextStyles.bodySm.copyWith(height: 1.35);
    var width =
        math.min(MediaQuery.sizeOf(context).width, ReadableWidth.maxWidth) -
        AppGrouped.margin * 2 -
        ExploreBookItem.coverWidth -
        AppSpacing.lg;
    if (isInBookshelf) {
      width -= AppSpacing.sm + _ShelfBadgeSkeleton.widthFor(context);
    }
    final title = GroupedItemShape.text(
      context,
      context.zh(book.name),
      style: titleStyle,
      width: width,
      maxLines: 2,
    );
    final metaHeight =
        MediaQuery.textScalerOf(context).scale(metaStyle.fontSize!) *
        metaStyle.height!;
    var textHeight = title.height + 2 + metaHeight;
    if (book.latestChapterTitle case final chapter? when chapter.isNotEmpty) {
      textHeight +=
          2 +
          GroupedItemShape.text(
            context,
            '最新：${context.zh(chapter)}',
            style: metaStyle,
            width: width,
            maxLines: 1,
          ).height;
    }
    return math.max(ExploreBookItem.coverHeight, textHeight) +
        AppSpacing.md * 2;
  }

  @override
  Widget build(BuildContext context) {
    const rowHeight = ExploreBookItem.coverHeight + AppSpacing.md * 2;
    return ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fill = _countToFill(constraints, padding, rowHeight);
          final count = books.isEmpty ? fill : math.min(books.length, fill);
          return ListView.separated(
            // 同書源列表的骨架：整片每一幀都重畫，不每列各一層。
            addRepaintBoundaries: false,
            physics: const NeverScrollableScrollPhysics(),
            padding: padding,
            itemCount: count,
            separatorBuilder: (_, _) =>
                const InsetSeparator(indent: ExploreBookItem.textIndent),
            itemBuilder: (context, index) => _BookRowSkeleton(
              book: index < books.length ? books[index] : null,
              isInBookshelf:
                  index < books.length &&
                  (inBookshelf?.call(books[index]) ?? false),
            ),
          );
        },
      ),
    );
  }
}

class _BookRowSkeleton extends StatelessWidget {
  const _BookRowSkeleton({this.book, this.isInBookshelf = false});

  final SearchBook? book;
  final bool isInBookshelf;

  @override
  Widget build(BuildContext context) {
    final title = AppTextStyles.bodyBase.copyWith(
      height: 1.3,
      fontWeight: FontWeight.w600,
    );
    final meta = AppTextStyles.bodySm.copyWith(height: 1.35);
    final metaHeight =
        MediaQuery.textScalerOf(context).scale(meta.fontSize!) * meta.height!;
    final loaded = book;
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
          const SkeletonBox(
            width: ExploreBookItem.coverWidth,
            height: ExploreBookItem.coverHeight,
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 書還沒到只畫封面：還不知道書名多長，先畫的長條到了一定要
                // 變長變短；書到了才照書名補上長條（docs/design/loading.md「骨架換場」）。
                if (loaded != null) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _BookTextBars(
                          text: context.zh(loaded.name),
                          style: title,
                          maxLines: 2,
                        ),
                      ),
                      if (isInBookshelf) ...[
                        const SizedBox(width: AppSpacing.sm),
                        const _ShelfBadgeSkeleton(),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  SizedBox(
                    height: metaHeight,
                    child: _BookTextBars(
                      text: ExploreBookItem.metaOf(context, loaded),
                      style: meta,
                      maxLines: 1,
                    ),
                  ),
                  if (loaded.latestChapterTitle case final chapter?
                      when chapter.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    _BookTextBars(
                      text: '最新：${context.zh(chapter)}',
                      style: meta,
                      maxLines: 1,
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 已經收到文字時，依 TextPainter 的每行字框畫相同寬度與行高的條。
class _BookTextBars extends StatelessWidget {
  const _BookTextBars({
    required this.text,
    required this.style,
    required this.maxLines,
  });

  final String text;
  final TextStyle style;
  final int maxLines;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final shape = GroupedItemShape.text(
        context,
        text,
        style: style,
        width: constraints.maxWidth,
        maxLines: maxLines,
      );
      return SkeletonShapes(height: shape.height, shapes: (_) => shape.marks);
    },
  );
}

/// 右側「書架」膠囊的形狀跟著相同的字級與水平內距。
class _ShelfBadgeSkeleton extends StatelessWidget {
  const _ShelfBadgeSkeleton();

  static GroupedItemShape _labelShape(BuildContext context) =>
      GroupedItemShape.text(
        context,
        '書架',
        style: AppTextStyles.labelXs.copyWith(
          height: 1.3,
          fontWeight: FontWeight.w600,
        ),
        width: double.infinity,
        maxLines: 1,
      );

  static double widthFor(BuildContext context) =>
      _labelShape(context).width! + AppSpacing.sm * 2;

  @override
  Widget build(BuildContext context) {
    final label = _labelShape(context);
    return SkeletonBox(
      width: widthFor(context),
      height: label.height + 4,
      borderRadius: AppRadius.pillShape,
    );
  }
}

/// 從頂端內距排到畫面底緣要幾列。底部內距只是捲到底時多留的空白，真正的
/// 清單在它上面照樣有列，骨架也要畫到底緣。
int _countToFill(BoxConstraints constraints, EdgeInsets padding, double row) {
  final extent = constraints.maxHeight - padding.top;
  return extent <= 0 ? 1 : (extent / row).ceil();
}
