import 'package:flutter/widgets.dart';

import '../theme/app_text_styles.dart';
import '../theme/app_tokens.dart';
import 'grouped_list.dart';
import 'number_stepper_row.dart';
import 'skeleton.dart';
import 'swipe_actions.dart';

/// 分組清單進場時的骨架（[GroupedListView]，ADR 0029）：每一項（通常是一組
/// [GroupedSection]）畫成卡片底、組標題條、每列的文字條與圖示方塊，整個
/// 畫面的骨架只用一個 [SkeletonShapes]。
///
/// 幾何照上次看過同一頁時記下的版面（[GroupedListLayouts]）；沒有紀錄時照列
/// 的種類估：一般列 [AppGrouped.rowMinHeight]、帶副標的列
/// [AppGrouped.rowTallMinHeight]，不是分組的項目高度 0（只在第一次看這一頁
/// 時，換成內容的那一下會往下推）。
@immutable
class GroupedItemShape {
  const GroupedItemShape(this.height, {this.rows});

  /// 這一項的總高，含組上方的間距與組標題。
  final double height;

  /// 卡片裡每一列的上緣（相對這一項）與高度；null 時不畫卡片。
  final List<(double, double)>? rows;

  /// 照列的種類估出來的樣子。
  static GroupedItemShape estimate(Widget item, TextScaler scaler) {
    if (item is! GroupedSection) return const GroupedItemShape(0);
    var top = item.topGap;
    if (item.header != null || item.headerTrailing != null) {
      top += _headerLine(scaler) + AppSpacing.sm;
    }
    final rows = <(double, double)>[];
    for (final row in item.children) {
      if (rows.isNotEmpty) top += AppGlass.hairline;
      final height = _hasSubtitle(row)
          ? AppGrouped.rowTallMinHeight
          : AppGrouped.rowMinHeight;
      rows.add((top, height));
      top += height;
    }
    if (item.footer != null) {
      final footer = AppTextStyles.bodySm;
      top +=
          AppSpacing.sm + scaler.scale(footer.fontSize!) * (footer.height ?? 1);
    }
    return GroupedItemShape(top, rows: rows);
  }

  /// 照畫面上排好的樣子量：[slot] 是包著 [item] 的那一項。[item] 還沒建
  /// （輪到才建，[CoverRevealSlot]）或量不到每一列時傳回 null。
  static GroupedItemShape? measure(Element slot, Widget item) {
    final box = slot.renderObject;
    if (box is! RenderBox || !box.hasSize) return null;
    final rows = item is GroupedSection ? item.children : const <Widget>[];
    final found = <Widget, RenderBox>{};
    var built = false;
    void visit(Element element) {
      final widget = element.widget;
      if (identical(widget, item)) built = true;
      if (rows.any((row) => identical(row, widget))) {
        final rowBox = element.renderObject;
        if (rowBox is RenderBox && rowBox.hasSize) found[widget] = rowBox;
        return;
      }
      element.visitChildren(visit);
    }

    slot.visitChildren(visit);
    if (!built) return null;
    if (item is! GroupedSection) return GroupedItemShape(box.size.height);
    if (found.length != rows.length) return null;
    return GroupedItemShape(
      box.size.height,
      rows: [
        for (final row in rows)
          (
            found[row]!.localToGlobal(Offset.zero, ancestor: box).dy,
            found[row]!.size.height,
          ),
      ],
    );
  }
}

/// 各頁上次換成內容時的版面，以頁面的結構、寬度與字級區分；只留在記憶體，
/// 開 App 後第一次進一頁時照估的畫。
abstract final class GroupedListLayouts {
  static final Map<String, List<GroupedItemShape?>> _byPage = {};

  /// 同一個結構、寬度與字級才沿用；組的標題、列數或有無附註變了就是另一個。
  static String keyOf(List<Widget> items, double width, TextScaler scaler) {
    final parts = [width.toStringAsFixed(0), scaler.scale(100).toString()];
    for (final item in items) {
      parts.add(switch (item) {
        GroupedSection(:final header, :final children, :final footer) =>
          '$header/${children.length}/${footer != null}',
        _ => '${item.runtimeType}',
      });
    }
    return parts.join('|');
  }

  static List<GroupedItemShape?>? of(String key) => _byPage[key];

  static void remember(String key, List<GroupedItemShape?> shapes) =>
      _byPage[key] = shapes;
}

/// 整個清單的骨架：從 [top] 起依序畫 [items]，畫到畫面底就停。
class GroupedListSkeleton extends StatelessWidget {
  const GroupedListSkeleton({
    super.key,
    required this.items,
    required this.shapes,
    required this.top,
    required this.cardFill,
  });

  final List<Widget> items;
  final List<GroupedItemShape> shapes;
  final double top;
  final Color cardFill;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final header = scaler.scale(AppTextStyles.uiSm.fontSize!);
    final title = scaler.scale(AppTextStyles.bodyBase.fontSize!);
    final subtitle = scaler.scale(AppTextStyles.bodySm.fontSize!);
    return SkeletonShapes(
      height: 0,
      shapes: (size) {
        final out = <SkeletonShape>[];
        var y = top;
        for (var i = 0; i < items.length && y < size.height; i++) {
          final item = items[i];
          final shape = shapes[i];
          final rows = shape.rows;
          if (item is GroupedSection && rows != null && rows.isNotEmpty) {
            final margin = (item.margin ?? _defaultMargin).resolve(
              Directionality.of(context),
            );
            final left = margin.left;
            final right = size.width - margin.right;
            final textMax = (right - left) * 0.6;
            if (item.header case final text?) {
              final lineTop = y + item.topGap;
              final line = _headerLine(scaler);
              out.add(
                SkeletonShape(
                  Rect.fromLTWH(
                    left + AppGrouped.rowPadding,
                    lineTop + (line - header) / 2,
                    _textWidth(text.length, header, textMax),
                    header,
                  ),
                ),
              );
            }
            final (firstTop, _) = rows.first;
            final (lastTop, lastHeight) = rows.last;
            out.add(
              SkeletonShape(
                Rect.fromLTRB(
                  left,
                  y + firstTop,
                  right,
                  y + lastTop + lastHeight,
                ),
                radius: AppGrouped.cardRadius,
                fill: cardFill,
              ),
            );
            for (var r = 0; r < rows.length && r < item.children.length; r++) {
              final row = item.children[r];
              final (rowTop, rowHeight) = rows[r];
              final centre = y + rowTop + rowHeight / 2;
              var textLeft = left + AppGrouped.rowPadding;
              if (groupedRowHasLeading(row)) {
                out.add(
                  SkeletonShape(
                    Rect.fromCenter(
                      center: Offset(
                        textLeft + AppGrouped.iconTile / 2,
                        centre,
                      ),
                      width: AppGrouped.iconTile,
                      height: AppGrouped.iconTile,
                    ),
                    radius: const BorderRadius.all(
                      Radius.circular(AppGrouped.iconTileRadius),
                    ),
                  ),
                );
                textLeft = left + AppGrouped.separatorIndentWithIcon;
              }
              final width = _textWidth(
                _rowTitle(row)?.length ?? 4,
                title,
                textMax,
              );
              if (_hasSubtitle(row)) {
                const gap = 4.0;
                final block = title + gap + subtitle;
                final blockTop = centre - block / 2;
                out
                  ..add(
                    SkeletonShape(
                      Rect.fromLTWH(textLeft, blockTop, width, title),
                    ),
                  )
                  ..add(
                    SkeletonShape(
                      Rect.fromLTWH(
                        textLeft,
                        blockTop + title + gap,
                        textMax * 0.8,
                        subtitle,
                      ),
                    ),
                  );
              } else {
                out.add(
                  SkeletonShape(
                    Rect.fromLTWH(textLeft, centre - title / 2, width, title),
                  ),
                );
              }
            }
          }
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

/// 組標題一行的高度。
double _headerLine(TextScaler scaler) {
  const style = AppTextStyles.uiSm;
  return scaler.scale(style.fontSize!) * (style.height ?? 1);
}

/// 中文一個字約一個字號寬；最長到 [max]。
double _textWidth(int characters, double fontSize, double max) =>
    (characters * fontSize).clamp(fontSize * 2, max);

/// 穿過常見外框找出列本身（同 [groupedRowHasLeading]）。
Widget _row(Widget widget) => switch (widget) {
  SwipeActions(:final child) => _row(child),
  KeyedSubtree(:final child) => _row(child),
  ProxyWidget(:final child) => _row(child),
  SingleChildRenderObjectWidget(:final child?) => _row(child),
  _ => widget,
};

String? _rowTitle(Widget widget) => switch (_row(widget)) {
  GroupedRow(:final title) => title,
  GroupedSwitchRow(:final title) => title,
  NumberStepperRow(:final label) => label,
  _ => null,
};

bool _hasSubtitle(Widget widget) => switch (_row(widget)) {
  GroupedRow(:final subtitle?) => subtitle.isNotEmpty,
  _ => false,
};
