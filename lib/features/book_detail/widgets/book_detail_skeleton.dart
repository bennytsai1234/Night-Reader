import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/lists/grouped_list.dart';
import 'package:night_reader/shared/widgets/skeleton/grouped_list_skeleton.dart';
import 'package:night_reader/shared/widgets/skeleton/skeleton.dart';
import 'package:night_reader/shared/widgets/skeleton/skeleton_text.dart';

import '../book_detail_provider.dart';
import 'book_info_header.dart';
import 'book_info_intro.dart';
import 'book_info_toc_bar.dart';
import 'book_toc_chapter_row.dart';

/// 書籍詳情頁首以下的資訊分組、簡介與目錄的骨架。放在 [Skeleton] 底下才會
/// 呼吸。
///
/// 資料還沒到（[loaded] 是 null）時照進頁時手上的書排：已有的來源、分類、
/// 字數、最新章節、簡介與章數照真正的文字量，還不知道的（書源狀態、簡介、
/// 章名）用固定長度。資料到了（[loaded]）就照頁面上的同一份資料、同一個
/// 元件排（書源問題、書源狀態、簡介、分卷、目前這一章、付費章節），每一
/// 條剛好換成那一段字，換場時版面不跳（docs/design/screens.md「書籍詳情」）。
class BookDetailSkeleton extends StatelessWidget {
  const BookDetailSkeleton({super.key, required this.book, this.loaded});

  /// 進頁時手上的書。
  final Book book;

  /// 資料到了的頁面資料；還在載入時是 null。
  final BookDetailProvider? loaded;

  /// 不知道章名時目錄列的佔位長度，輪流使用。
  static const List<double> _chapterWidths = [0.55, 0.4, 0.65, 0.5, 0.45];

  /// 目錄最多畫幾列：比一個畫面能露出的多，再多也看不到，只是多排。
  static const int _maxChapterRows = 16;

  /// 不知道章數時畫的列數。
  static const int _unknownChapterRows = 8;

  /// 不知道簡介時的佔位行（相對寬度）。
  static const List<double> _unknownIntroLines = [1.0, 1.0, 0.95, 0.6];

  static final TextStyle _rowStyle = AppTextStyles.bodyBase.copyWith(
    height: 1.3,
  );
  static final TextStyle _headerStyle = AppTextStyles.bodyBase.copyWith(
    fontWeight: FontWeight.w600,
    height: 1.3,
  );
  static final TextStyle _introStyle = AppTextStyles.bodyBase.copyWith(
    height: 1.6,
  );

  @override
  Widget build(BuildContext context) {
    final loaded = this.loaded;
    return ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: loaded == null ? _guessed(context) : _known(context, loaded),
      ),
    );
  }

  /// 資料到了：和 `BookDetailPage` 換上來的內容同樣的區塊。
  List<Widget> _known(BuildContext context, BookDetailProvider loaded) {
    final rows = loaded.filteredChapters.length;
    return [
      if (BookSourceIssue.of(loaded) case final issue?) _Shaped(issue),
      _Shaped(
        BookInfoDetails(
          book: loaded.book,
          statusChip: SourceStatusChip.of(loaded),
        ),
      ),
      _Shaped(BookInfoIntro(book: loaded.book)),
      _tocBar('目錄（共 ${loaded.tocVolumes.chapterCount} 章）'),
      for (var i = 0; i < math.min(rows, _maxChapterRows); i++)
        GroupedSliceItem(
          index: i,
          count: rows,
          child: _Shaped(bookTocRow(context, loaded, i)),
        ),
    ];
  }

  /// 資料還沒到：照進頁時手上的書。
  List<Widget> _guessed(BuildContext context) {
    final total = book.totalChapterNum;
    final chapterRows = total > 0
        ? math.min(total, _maxChapterRows)
        : _unknownChapterRows;
    final chapterCount = total > 0 ? total : chapterRows;
    final intro = book.getShownIntro();
    return [
      _Shaped(
        BookInfoDetails(
          book: book,
          // 書源狀態的小膠囊，字還不知道。
          statusChip: const SizedBox(
            width: 36,
            height: 18,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: AppRadius.pillShape,
              ),
            ),
          ),
        ),
      ),
      if (intro.isEmpty)
        GroupedSection(
          children: [
            GroupedContent(
              child: Column(
                children: [
                  for (final width in _unknownIntroLines)
                    SkeletonLine(style: _introStyle, widthFactor: width),
                ],
              ),
            ),
          ],
        )
      else
        _Shaped(BookInfoIntro(book: book)),
      _tocBar('目錄（共 ${total > 0 ? total : '000'} 章）'),
      for (var i = 0; i < chapterRows; i++)
        GroupedSliceItem(
          index: i,
          count: chapterCount,
          child: GroupedRow(
            title: '',
            titleWidget: SkeletonLine(
              style: _rowStyle,
              widthFactor: _chapterWidths[i % _chapterWidths.length],
            ),
            showChevron: false,
          ),
        ),
    ];
  }

  /// 同 BookInfoTocBar：粗字寫章數，右側三顆小圓鈕，上下一樣。
  Widget _tocBar(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppGrouped.margin + AppGrouped.rowPadding,
      AppGrouped.sectionGap,
      AppGrouped.margin,
      AppGrouped.sectionGap,
    ),
    child: Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            heightFactor: 1,
            // 和目錄列一樣，字大時照可用寬度換行。
            child: SkeletonText(title, style: _headerStyle),
          ),
        ),
        for (var i = 0; i < 3; i++)
          const Padding(
            padding: EdgeInsets.only(left: AppSpacing.sm),
            child: SkeletonBox(
              width: BookInfoTocBar.buttonSize,
              height: BookInfoTocBar.buttonSize,
              borderRadius: BorderRadius.all(
                Radius.circular(BookInfoTocBar.buttonSize / 2),
              ),
            ),
          ),
      ],
    ),
  );
}

/// [item] 的骨架：照它排出來的字與元件（[GroupedItemShape.of]），分組卡片
/// 的底照卡片的範圍鋪。
class _Shaped extends StatelessWidget {
  const _Shaped(this.item);

  final Widget item;

  @override
  Widget build(BuildContext context) {
    final card = AppChrome.of(context).groupedSurface;
    return LayoutBuilder(
      builder: (context, constraints) {
        final shape = GroupedItemShape.of(
          item,
          context: context,
          width: constraints.maxWidth,
        );
        return SkeletonShapes(
          height: shape.height,
          shapes: (_) => [
            if (shape.card case final rect?)
              SkeletonShape(rect, radius: AppGrouped.cardRadius, fill: card),
            ...shape.marks,
          ],
        );
      },
    );
  }
}
