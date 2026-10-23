import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_text_styles.dart';
import '../theme/app_tokens.dart';
import 'grouped_list.dart';
import 'skeleton.dart';
import 'swipe_actions.dart';

/// 分組清單裡自己給骨架樣子的一項：一般的列與組已經認得（[GroupedItemShape.of]），
/// 頁面自己的區塊（風格卡、色票列、分段控制、輸入框）實作這個介面，照元件
/// build 用的同一份版面常數與字樣，在 [width] 裡真的把字排出來。
abstract interface class GroupedSkeletonItem {
  GroupedItemShape skeletonShape(BuildContext context, {required double width});
}

/// 分組清單進場時的骨架（[GroupedListView]、[GroupedSheetContent]，ADR 0029）：
/// 每一行字一條、每個圖示、圖片、開關與色塊（列首圖示方塊、數值膠囊）一塊，
/// 卡片照卡片的範圍鋪底色；整個畫面的骨架只用一個 [SkeletonShapes]。
///
/// 每一項照元件本身算（[of]），不靠上次畫面的紀錄：第一次進一頁、換了字級
/// 或寬度，骨架都和換上的內容一樣。
@immutable
class GroupedItemShape {
  const GroupedItemShape(
    this.height, {
    this.width,
    this.card,
    this.rowHeights,
    this.marks = const [],
  });

  /// 這一項的總高，含組上方的間距與組標題。
  final double height;

  /// 不撐滿可用寬度的元件（列首、右側控件、組標題右側的按鈕）本身的寬；
  /// 撐滿的為 null。
  final double? width;

  /// 分組卡片每一列的高度；骨架底下還沒輪到的列照它佔位。
  final List<double>? rowHeights;

  /// 卡片的範圍（相對這一項）；不是分組卡片時為 null。
  final Rect? card;

  /// 字、圖示與色塊的位置（相對這一項）。
  final List<SkeletonShape> marks;

  /// 形狀與內容共用內距，不能只把骨架撐高而漏掉內容的留白。
  GroupedItemShape padded(EdgeInsets padding) => GroupedItemShape(
    height + padding.vertical,
    width: switch (width) {
      final width? => width + padding.horizontal,
      null => null,
    },
    card: card?.shift(padding.topLeft),
    rowHeights: rowHeights,
    marks: marksAt(padding.topLeft),
  );

  /// 每個形狀平移 [offset] 後的位置。
  List<SkeletonShape> marksAt(Offset offset) => [
    for (final mark in marks)
      SkeletonShape(mark.rect.shift(offset), radius: mark.radius),
  ];

  /// 放在 [width] 寬、置中排的 [Column] 裡：照自己的寬度擺在中間。
  GroupedItemShape centeredIn(double width) => GroupedItemShape(
    height,
    width: width,
    marks: marksAt(Offset((width - this.width!) / 2, 0)),
  );

  /// [text] 以 [style] 排在最寬 [width] 裡的樣子：和 [Text] 一樣先合併
  /// [context] 的預設字樣，照系統字級、行高規則（與 [strutStyle]）和語系排；
  /// 高度是那段字的高度，[GroupedItemShape.width] 是排出來的寬（照字的
  /// 寬度，[fill] 時撐滿 [width]，和父層給了固定寬度的 [Text] 一樣，
  /// [textAlign] 在這個寬度裡對齊）。每一行一條，和那一行字一樣寬、字號
  /// 一樣高，對著那一行字的中線。
  static GroupedItemShape text(
    BuildContext context,
    String text, {
    required TextStyle style,
    required double width,
    int? maxLines,
    TextAlign textAlign = TextAlign.start,
    StrutStyle? strutStyle,
    bool fill = false,
  }) => _paragraph(
    context,
    TextSpan(
      text: text,
      style: DefaultTextStyle.of(context).style.merge(style),
    ),
    width: width,
    maxLines: maxLines,
    textAlign: textAlign,
    strutStyle: strutStyle,
    fill: fill,
  );

  /// 同 [text]，給 [Text.rich] 這種一段裡有幾種字樣的字。
  static GroupedItemShape rich(
    BuildContext context,
    InlineSpan span, {
    required double width,
    int? maxLines,
  }) => _paragraph(
    context,
    TextSpan(style: DefaultTextStyle.of(context).style, children: [span]),
    width: width,
    maxLines: maxLines,
  );

  /// [text] 照 [Text] 的方式排在最寬 [maxWidth] 裡的大小（見 [text]）。
  static Size textSize(
    BuildContext context,
    String text, {
    required TextStyle style,
    required double maxWidth,
    int? maxLines,
  }) {
    final shape = GroupedItemShape.text(
      context,
      text,
      style: style,
      width: maxWidth,
      maxLines: maxLines,
    );
    return Size(shape.width!, shape.height);
  }

  /// [root] 是 [Text] 交給 [RenderParagraph] 的那一層（已合併預設字樣）。
  static GroupedItemShape _paragraph(
    BuildContext context,
    TextSpan root, {
    required double width,
    int? maxLines,
    TextAlign textAlign = TextAlign.start,
    StrutStyle? strutStyle,
    bool fill = false,
  }) {
    final defaults = DefaultTextStyle.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final maxWidth = math.max(0.0, width);
    final painter =
        TextPainter(
          text: root,
          textAlign: textAlign,
          strutStyle: strutStyle,
          textScaler: scaler,
          textDirection: Directionality.of(context),
          textHeightBehavior: defaults.textHeightBehavior,
          locale: Localizations.maybeLocaleOf(context),
          maxLines: maxLines,
          ellipsis: maxLines == null ? null : '…',
        )..layout(
          minWidth: fill && maxWidth.isFinite ? maxWidth : 0,
          maxWidth: maxWidth,
        );
    final shape = GroupedItemShape(
      painter.height,
      width: painter.width,
      marks: _lineMarks(painter, scaler.scale(root.style?.fontSize ?? 14)),
    );
    painter.dispose();
    return shape;
  }

  /// [item] 在 [width] 寬的清單（或卡片）裡的樣子：自己給樣子的元件
  /// （[GroupedSkeletonItem]：一般的列、步進列、頁面自己的區塊）照它給的，
  /// 組照組標題、每一列與附註排，常見的外框（內距、[Builder]、
  /// [ValueListenableBuilder]、[FutureBuilder]、滑動動作）穿過去找裡面的
  /// 元件。組的上緣往下超過 [until] 的列不算（高度記 0）。
  static GroupedItemShape of(
    Widget item, {
    required BuildContext context,
    required double width,
    double until = double.infinity,
  }) {
    final shape = item is GroupedSection
        ? _section(item, context, width, until: until)
        : maybeOf(item, context: context, width: width);
    assert(
      shape != null,
      '${item.runtimeType} 算不出骨架：讓它實作 GroupedSkeletonItem（ADR 0029）',
    );
    return shape ?? const GroupedItemShape(0);
  }

  /// 同 [of]；認不出的元件傳回 null。
  static GroupedItemShape? maybeOf(
    Widget item, {
    required BuildContext context,
    required double width,
  }) {
    GroupedItemShape? inner(
      Widget child, [
      EdgeInsets inset = EdgeInsets.zero,
    ]) => maybeOf(
      child,
      context: context,
      width: width - inset.horizontal,
    )?.padded(inset);
    return switch (item) {
      final GroupedSkeletonItem shaped => shaped.skeletonShape(
        context,
        width: width,
      ),
      GroupedSection() => _section(item, context, width),
      GroupedContent(:final padding, :final child) => inner(
        child,
        padding.resolve(Directionality.of(context)),
      ),
      Padding(:final padding, :final child?) => inner(
        child,
        padding.resolve(Directionality.of(context)),
      ),
      SizedBox(:final height?, child: null) => GroupedItemShape(height),
      Text(:final data?, :final style, :final maxLines, :final textAlign) ||
      SelectableText(
        :final data?,
        :final style,
        :final maxLines,
        :final textAlign,
      ) => GroupedItemShape.text(
        context,
        data,
        style: style ?? const TextStyle(),
        width: width,
        maxLines: maxLines,
        textAlign: textAlign ?? TextAlign.start,
        fill: true,
      ),
      // 置中的小元件（轉圈）照它本身的大小放在中間。
      Center(:final child?) => switch (groupedPartShape(child, context)) {
        final part => GroupedItemShape(
          part.height,
          marks: part.marksAt(Offset((width - part.width!) / 2, 0)),
        ),
      },
      Builder(:final builder) => inner(builder(context)),
      // 骨架和 FutureBuilder 第一次建時一樣，都還在等。
      FutureBuilder(initialData: null) => inner(_buildFuture(item, context)),
      // builder 的參數型別是 T，從 ValueListenableBuilder<Object?> 取用會被
      // 型別檢查擋下，改成動態呼叫。
      ValueListenableBuilder() => inner(_buildListenable(item, context)),
      KeyedSubtree(:final child) ||
      SwipeActions(:final child) ||
      Semantics(child: final child?) ||
      MergeSemantics(child: final child?) ||
      RepaintBoundary(child: final child?) => inner(child),
      _ => null,
    };
  }

  static Widget _buildListenable(Widget builder, BuildContext context) {
    final dynamic widget = builder;
    return widget.builder(context, widget.valueListenable.value, widget.child)
        as Widget;
  }

  /// 沒有資料的等待狀態用 `AsyncSnapshot<Never>`，任何 T 的 builder 都收。
  static Widget _buildFuture(Widget builder, BuildContext context) {
    final dynamic widget = builder;
    return widget.builder(context, const AsyncSnapshot<Never>.waiting())
        as Widget;
  }

  /// 組標題、卡片裡的每一列（列與列之間一條髮絲線）與附註，和
  /// [GroupedSection.build] 排的一樣。
  static GroupedItemShape _section(
    GroupedSection section,
    BuildContext context,
    double width, {
    double until = double.infinity,
  }) {
    final margin = (section.margin ?? _defaultMargin).resolve(
      Directionality.of(context),
    );
    final left = margin.left;
    final right = width - margin.right;
    final marks = <SkeletonShape>[];

    var top = section.topGap;
    if (section.header != null || section.headerTrailing != null) {
      // 組標題與右側按鈕在同一列、對齊下緣。
      final textLeft = left + AppGrouped.rowPadding;
      final textRight = right - AppGrouped.rowPadding;
      // 右側照它本身的寬度排，標題用剩下的寬度。
      final trailing = switch (section.headerTrailing) {
        final widget? => groupedPartShape(widget, context),
        null => null,
      };
      final trailingWidth = trailing?.width ?? 0;
      final header = GroupedItemShape.text(
        context,
        section.header ?? '',
        style: GroupedSectionHeader.textStyle(context),
        width: textRight - textLeft - trailingWidth,
      );
      final line = math.max(header.height, trailing?.height ?? 0);
      marks.addAll(
        header.marksAt(Offset(textLeft, top + line - header.height)),
      );
      if (trailing != null) {
        marks.addAll(
          trailing.marksAt(
            Offset(textRight - trailingWidth, top + line - trailing.height),
          ),
        );
      }
      top += line + AppSpacing.sm;
    }
    final cardTop = top;
    final rowHeights = <double>[];
    for (final (index, child) in section.children.indexed) {
      // 畫面底以下的列骨架畫不到，也不排隊等（和組一起建），不必算。
      if (top >= until) {
        rowHeights.add(0);
        continue;
      }
      if (index > 0) top += AppGlass.hairline;
      final row = of(child, context: context, width: right - left);
      rowHeights.add(row.height);
      marks.addAll(row.marksAt(Offset(left, top)));
      top += row.height;
    }
    final card = Rect.fromLTRB(left, cardTop, right, top);
    if (section.footer case final text? when top < until) {
      top += AppSpacing.sm;
      final footer = GroupedItemShape.text(
        context,
        text,
        style: AppTextStyles.bodySm,
        width: right - left - AppGrouped.rowPadding * 2,
      );
      marks.addAll(footer.marksAt(Offset(left + AppGrouped.rowPadding, top)));
      top += footer.height;
    }
    return GroupedItemShape(
      top,
      card: card,
      rowHeights: rowHeights,
      marks: marks,
    );
  }
}

/// 整個清單的骨架：從 [top] 起依序畫 [shapes]，畫到畫面底就停。
class GroupedListSkeleton extends StatelessWidget {
  const GroupedListSkeleton({
    super.key,
    required this.shapes,
    required this.top,
    required this.cardFill,
  });

  final List<GroupedItemShape> shapes;
  final double top;
  final Color cardFill;

  @override
  Widget build(BuildContext context) {
    return SkeletonShapes(
      height: 0,
      shapes: (size) {
        final out = <SkeletonShape>[];
        var y = top;
        for (final shape in shapes) {
          if (y >= size.height) break;
          final offset = Offset(0, y);
          if (shape.card case final card?) {
            out.add(
              SkeletonShape(
                card.shift(offset),
                radius: AppGrouped.cardRadius,
                fill: cardFill,
              ),
            );
          }
          out.addAll(shape.marksAt(offset));
          y += shape.height;
        }
        return out;
      },
    );
  }
}

const EdgeInsetsGeometry _defaultMargin = EdgeInsets.symmetric(
  horizontal: AppGrouped.margin,
);

/// 一段字每一行的佔位條：照排出來的寬度，高度是字號，對齊那一行的中線。
/// 圖示也是一個字，畫成和字形一樣大的圓角方塊。
List<SkeletonShape> _lineMarks(TextPainter painter, double fontSize) {
  final text = painter.text!.toPlainText(includeSemanticsLabels: false);
  if (text.trim().isEmpty) return const [];
  final lines = <Rect>[];
  for (final box in painter.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: text.length),
  )) {
    final rect = box.toRect();
    if (rect.top >= painter.height || rect.width <= 0) continue;
    final index = lines.indexWhere(
      (line) => (line.center.dy - rect.center.dy).abs() < rect.height / 2,
    );
    if (index < 0) {
      lines.add(rect);
    } else {
      lines[index] = lines[index].expandToInclude(rect);
    }
  }
  return [for (final line in lines) _lineMark(line, fontSize, painter.width)];
}

SkeletonShape _lineMark(Rect line, double fontSize, double maxWidth) {
  final height = math.min(fontSize, line.height);
  // 至少畫成方塊（單一個字或圖示），但不超出這段字的寬。
  final width = math.min(math.max(line.width, height), maxWidth);
  return SkeletonShape(
    Rect.fromLTWH(line.left, line.center.dy - height / 2, width, height),
    radius: BorderRadius.circular(height / 4),
  );
}
