import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/services/chinese_display.dart';
import 'package:night_reader/core/utils/string_utils.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';

import 'book_info_toc_bar.dart';

/// 書籍詳情載入中，頁首以下的資訊分組、簡介與目錄的骨架。放在 [Skeleton]
/// 底下才會呼吸。
///
/// 照真正版面的元件與間距排，進頁時手上已有的資料（搜尋結果或書架上的
/// 書：來源、分類、字數、最新章節、簡介、章數）照真正的文字量出長條的寬度
/// 與行數，骨架換成內容時每一條剛好換成那一段字，版面不跳；還不知道的
/// （書源狀態、章節名稱）用固定長度。
class BookDetailSkeleton extends StatelessWidget {
  const BookDetailSkeleton({super.key, required this.book});

  final Book book;

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
  static final TextStyle _subtitleStyle = AppTextStyles.bodySm.copyWith(
    height: 1.3,
  );
  static final TextStyle _headerStyle = AppTextStyles.uiSm.copyWith(
    fontWeight: FontWeight.w400,
  );
  static final TextStyle _introStyle = AppTextStyles.bodyBase.copyWith(
    height: 1.6,
  );

  @override
  Widget build(BuildContext context) {
    final total = book.totalChapterNum;
    final chapterRows = total > 0
        ? math.min(total, _maxChapterRows)
        : _unknownChapterRows;
    final chapterCount = total > 0 ? total : chapterRows;
    final intro = book.getDisplayIntro()?.trim() ?? '';
    return ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _details(context),
          // 同 BookInfoIntro：組標題「簡介」與一段正文。
          Padding(
            padding: const EdgeInsets.only(top: AppGrouped.sectionGap),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppGrouped.margin + AppGrouped.rowPadding,
                    0,
                    AppGrouped.margin + AppGrouped.rowPadding,
                    AppSpacing.sm,
                  ),
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    heightFactor: 1,
                    child: _TextBar('簡介', style: _headerStyle),
                  ),
                ),
                GroupedSection(
                  topGap: 0,
                  children: [
                    GroupedContent(
                      child: intro.isEmpty
                          ? Column(
                              children: [
                                for (final width in _unknownIntroLines)
                                  SkeletonLine(
                                    style: _introStyle,
                                    widthFactor: width,
                                  ),
                              ],
                            )
                          : _ParagraphBars(
                              context.zh(intro),
                              style: _introStyle,
                            ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // 同 BookInfoTocBar：組標題寫章數，右側三顆小圓鈕。
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppGrouped.margin + AppGrouped.rowPadding,
              AppGrouped.sectionGap - AppSpacing.md,
              AppGrouped.margin,
              AppSpacing.sm,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    heightFactor: 1,
                    child: _TextBar(
                      '目錄（共 ${total > 0 ? total : '000'} 章）',
                      style: _headerStyle,
                    ),
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
          ),
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
        ],
      ),
    );
  }

  /// 同 BookInfoDetails：來源（含書源狀態與箭頭）、分類、字數、最新章節。
  Widget _details(BuildContext context) {
    final kind = StringUtils.kindLabels(context.zh(book.kind ?? '')).join('、');
    final wordCount = StringUtils.displayWordCount(book.wordCount, book.kind);
    final latest = context.zh(book.latestChapterTitle ?? '').trim();
    final valueWidth = MediaQuery.sizeOf(context).width * 0.4;
    Widget value(String text) => ConstrainedBox(
      constraints: BoxConstraints(maxWidth: valueWidth),
      child: _TextBar(text, style: _rowStyle),
    );
    return GroupedSection(
      children: [
        GroupedRow(
          title: '來源',
          titleWidget: _TextBar('來源', style: _rowStyle),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              value(book.originName),
              if (!book.isLocal) ...[
                const SizedBox(width: AppSpacing.md),
                // 書源狀態的小膠囊（SourceStatusChip），字還不知道。
                const SkeletonBox(
                  width: 36,
                  height: 18,
                  borderRadius: AppRadius.pillShape,
                ),
              ],
            ],
          ),
          showChevron: !book.isLocal,
        ),
        if (kind.isNotEmpty)
          GroupedRow(
            title: '分類',
            titleWidget: _TextBar('分類', style: _rowStyle),
            trailing: value(kind),
          ),
        if (wordCount.isNotEmpty)
          GroupedRow(
            title: '字數',
            titleWidget: _TextBar('字數', style: _rowStyle),
            trailing: value(wordCount),
          ),
        if (latest.isNotEmpty)
          GroupedRow(
            title: '最新章節',
            // 帶副標的列最少 60 高；這裡的副標是骨架，自己撐到同樣高。
            titleWidget: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: AppGrouped.rowTallMinHeight - AppSpacing.md * 2,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TextBar('最新章節', style: _rowStyle),
                  const SizedBox(height: 2),
                  _TextBar(latest, style: _subtitleStyle),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// 一行字的骨架：照 [text] 以 [style] 排成一行（放不下時截斷）的寬高佔位，
/// 中間畫一條和字一樣高的圓角條（同 [SkeletonLine]）。
class _TextBar extends StatelessWidget {
  const _TextBar(this.text, {required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final fontSize = MediaQuery.textScalerOf(context)
        .scale(style.fontSize ?? AppTextStyles.bodyBase.fontSize!);
    return Stack(
      alignment: Alignment.centerLeft,
      children: [
        Visibility.maintain(
          visible: false,
          child: Text(
            text,
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Positioned.fill(
          child: Center(
            child: SkeletonBox(
              width: double.infinity,
              height: fontSize * Skeleton.barHeightFactor,
            ),
          ),
        ),
      ],
    );
  }
}

/// 一段字的骨架：照 [text] 以 [style] 在可用寬度裡換行，每一行在那一行字的
/// 位置與寬度畫一條和字一樣高的圓角條，總高度與那段字相同。
class _ParagraphBars extends StatelessWidget {
  const _ParagraphBars(this.text, {required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    // 與 Text 相同：先合併頁面的預設字樣（字族等），再照系統字級放大。
    final defaults = DefaultTextStyle.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final merged = defaults.style.merge(style);
    final barHeight =
        textScaler.scale(merged.fontSize ?? 14) * Skeleton.barHeightFactor;
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: merged),
          textDirection: Directionality.of(context),
          textScaler: textScaler,
          textHeightBehavior: defaults.textHeightBehavior,
          locale: Localizations.maybeLocaleOf(context),
        )..layout(maxWidth: constraints.maxWidth);
        final lines = painter.computeLineMetrics();
        final height = painter.height;
        painter.dispose();
        return SizedBox(
          width: constraints.maxWidth,
          height: height,
          child: Stack(
            children: [
              for (final line in lines)
                if (line.width > 0)
                  Positioned(
                    left: line.left,
                    width: line.width,
                    top:
                        line.baseline -
                        line.ascent +
                        (line.ascent + line.descent - barHeight) / 2,
                    height: barHeight,
                    child: const SkeletonBox(),
                  ),
            ],
          ),
        );
      },
    );
  }
}
