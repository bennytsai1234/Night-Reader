import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_text_styles.dart';
import '../theme/app_tokens.dart';
import 'grouped_list.dart';
import 'number_stepper_row.dart';
import 'skeleton.dart';
import 'swipe_actions.dart';

/// 不是一般分組列的區塊（色票列、分段控制、輸入框），自己給骨架的樣子：
/// 高度照區塊本身的版面常數與字樣算，和換上的內容一樣高。
abstract interface class GroupedSkeletonItem {
  GroupedItemShape skeletonShape(BuildContext context, {required double width});
}

/// 分組清單進場時的骨架（[GroupedListView]，ADR 0029）：照真的畫面畫，每一
/// 行字一條、每個圖示、圖片、開關與色塊（列首圖示方塊、數值膠囊）一塊，
/// 卡片照卡片的範圍鋪底色；整個畫面的骨架只用一個 [SkeletonShapes]。
///
/// 樣子是上次換成內容時從畫面上量的（[GroupedItemShape.measure]），存在
/// 偏好設定裡（[GroupedListLayouts]），重開 App 也照著畫；從來沒看過的頁面
/// 照列的種類估（[GroupedItemShape.estimate]）。
@immutable
class GroupedItemShape {
  const GroupedItemShape(
    this.height, {
    this.card,
    this.rowHeights,
    this.marks = const [],
  });

  /// 這一項的總高，含組上方的間距與組標題。
  final double height;

  /// 分組卡片每一列的高度；骨架底下還沒輪到的列照它佔位。
  final List<double>? rowHeights;

  /// 卡片的範圍（相對這一項）；不是分組卡片時為 null。
  final Rect? card;

  /// 字、圖示與色塊的位置（相對這一項）。
  final List<SkeletonShape> marks;

  /// 形狀與內容共用內距，不能只把骨架撐高而漏掉內容的留白。
  GroupedItemShape padded(EdgeInsets padding) => GroupedItemShape(
    height + padding.vertical,
    card: card?.shift(padding.topLeft),
    rowHeights: rowHeights,
    marks: [
      for (final mark in marks)
        SkeletonShape(
          mark.rect.shift(padding.topLeft),
          radius: mark.radius,
          fill: mark.fill,
        ),
    ],
  );

  /// [text] 以 [style] 在 [width] 裡排出來的樣子：和 [Text] 一樣先合併
  /// [context] 的預設字樣，照系統字級、行高規則與語系排，高度就是那段字的
  /// 高度。自訂區塊的骨架用它，第一次打開就和換上的字一樣高。
  static GroupedItemShape text(
    BuildContext context,
    String text, {
    required TextStyle style,
    required double width,
  }) {
    final defaults = DefaultTextStyle.of(context);
    final merged = defaults.style.merge(style);
    final scaler = MediaQuery.textScalerOf(context);
    final painter = TextPainter(
      text: TextSpan(text: text, style: merged),
      textScaler: scaler,
      textDirection: Directionality.of(context),
      textHeightBehavior: defaults.textHeightBehavior,
      locale: Localizations.maybeLocaleOf(context),
    )..layout(maxWidth: math.max(0, width));
    final font = scaler.scale(merged.fontSize ?? 14);
    final shape = GroupedItemShape(
      painter.height,
      marks: [
        for (final line in painter.computeLineMetrics())
          _bar(
            line.left,
            line.baseline - line.ascent + line.height / 2,
            line.width,
            math.min(font, line.height),
          ),
      ],
    );
    painter.dispose();
    return shape;
  }

  /// 一般列與帶副標的列的高度、步進列與開關列右側的控件照元件本身的尺寸；
  /// 包在私有元件裡認不出種類的列只畫標題條。不是一般分組列的區塊
  /// （[GroupedSkeletonItem]）照它自己給的形狀，組標題與附註照字排出來的
  /// 高度：面板（[GroupedSheetContent]）的高度就是這些高度加起來。
  static GroupedItemShape estimate(
    Widget item, {
    required BuildContext context,
    required double width,
  }) {
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    if (item case GroupedSkeletonItem shapeItem) {
      return shapeItem.skeletonShape(context, width: width);
    }
    if (item is GroupedContent) {
      final padding = item.padding.resolve(direction);
      final inner = estimate(
        item.child,
        context: context,
        width: width - padding.horizontal,
      );
      return inner.height > 0 ? inner.padded(padding) : inner;
    }
    if (item is NumberStepperRowLike) {
      return const GroupedItemShape(_stepperHeight);
    }
    if (item case SizedBox(:final height?)) return GroupedItemShape(height);
    if (item is! GroupedSection) return const GroupedItemShape(0);
    final margin = (item.margin ?? _defaultMargin).resolve(direction);
    final left = margin.left;
    final right = width - margin.right;
    final textMax = (right - left) * 0.6;
    final header = scaler.scale(AppTextStyles.uiSm.fontSize!);
    final title = scaler.scale(AppTextStyles.bodyBase.fontSize!);
    final small = scaler.scale(AppTextStyles.bodySm.fontSize!);
    final marks = <SkeletonShape>[];

    var top = item.topGap;
    if (item.header != null || item.headerTrailing != null) {
      final line = text(
        context,
        item.header ?? '',
        style: GroupedSectionHeader.textStyle(context),
        width: right - left - AppGrouped.rowPadding * 2,
      ).height;
      if (item.header case final text?) {
        marks.add(
          _bar(
            left + AppGrouped.rowPadding,
            top + line / 2,
            _textWidth(text.length, header, textMax),
            header,
          ),
        );
      }
      top += line + AppSpacing.sm;
    }
    final cardTop = top;
    final rowHeights = <double>[];
    for (final (index, child) in item.children.indexed) {
      if (index > 0) top += AppGlass.hairline;
      final row = _row(child);
      final custom = estimate(child, context: context, width: right - left);
      final height = custom.height > 0
          ? custom.height
          : switch (row) {
              NumberStepperRowLike() => _stepperHeight,
              GroupedRow(:final subtitle?) when subtitle.isNotEmpty =>
                AppGrouped.rowTallMinHeight,
              _ => math.max(
                AppGrouped.rowMinHeight,
                AppSpacing.md * 2 +
                    math.max(
                      title * 1.3,
                      groupedRowHasLeading(child) ? AppGrouped.iconTile : 0,
                    ),
              ),
            };
      rowHeights.add(height);
      if (custom.marks.isNotEmpty) {
        for (final mark in custom.marks) {
          marks.add(
            SkeletonShape(
              mark.rect.shift(Offset(left, top)),
              radius: mark.radius,
              fill: mark.fill,
            ),
          );
        }
        top += height;
        continue;
      }
      final centre = top + height / 2;
      var textLeft = left + AppGrouped.rowPadding;
      if (groupedRowHasLeading(child)) {
        marks.add(
          SkeletonShape(
            Rect.fromCenter(
              center: Offset(textLeft + AppGrouped.iconTile / 2, centre),
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
      final titleWidth = _textWidth(
        _rowTitle(row)?.length ?? 4,
        title,
        textMax,
      );
      var end = right - AppGrouped.rowPadding;
      switch (row) {
        case NumberStepperRowLike():
          // 「－」、數值膠囊、「＋」，和步進列一樣大。
          const button = 36.0;
          const target = 48.0;
          final plus = end - target / 2;
          final valueRight = end - target - AppSpacing.sm;
          final valueLeft = valueRight - 64;
          final minus = valueLeft - AppSpacing.sm - target / 2;
          marks
            ..add(_circle(Offset(minus, centre), button))
            ..add(
              SkeletonShape(
                Rect.fromLTRB(
                  valueLeft,
                  centre - button / 2,
                  valueRight,
                  centre + button / 2,
                ),
                radius: AppRadius.pillShape,
              ),
            )
            ..add(_circle(Offset(plus, centre), button));
        case GroupedSwitchRow():
          marks.add(
            SkeletonShape(
              Rect.fromLTRB(
                end - GroupedSwitch.trackWidth,
                centre - GroupedSwitch.trackHeight / 2,
                end,
                centre + GroupedSwitch.trackHeight / 2,
              ),
              radius: AppRadius.pillShape,
            ),
          );
        case GroupedRow(:final value, :final onTap, :final trailing):
          if (onTap != null && trailing == null) {
            // 箭頭。
            marks.add(_bar(end - 14, centre, 10, 14));
            end -= 22 + AppSpacing.sm;
          }
          if (value case final text?) {
            final valueWidth = _textWidth(text.length, title, textMax / 2);
            marks.add(_bar(end - valueWidth, centre, valueWidth, title));
          }
      }
      if (row case GroupedRow(:final subtitle?) when subtitle.isNotEmpty) {
        const gap = 2.0;
        final block = title * 1.3 + gap + small * 1.3;
        final blockTop = centre - block / 2;
        marks
          ..add(_bar(textLeft, blockTop + title * 0.65, titleWidth, title))
          ..add(
            _bar(
              textLeft,
              blockTop + title * 1.3 + gap + small * 0.65,
              textMax * 0.8,
              small,
            ),
          );
      } else {
        marks.add(_bar(textLeft, centre, titleWidth, title));
      }
      top += height;
    }
    final card = Rect.fromLTRB(left, cardTop, right, top);
    if (item.footer case final text?) {
      top += AppSpacing.sm;
      final line = GroupedItemShape.text(
        context,
        text,
        style: AppTextStyles.bodySm,
        width: right - left - AppGrouped.rowPadding * 2,
      ).height;
      marks.add(
        _bar(
          left + AppGrouped.rowPadding,
          top + line / 2,
          _textWidth(text.length, small, textMax),
          small,
        ),
      );
      top += line;
    }
    return GroupedItemShape(
      top,
      card: card,
      rowHeights: rowHeights,
      marks: marks,
    );
  }

  /// 照畫面上排好的樣子量：[slot] 是包著 [item] 的那一項，[visible] 是它
  /// 上緣到畫面底的距離，骨架只畫第一個畫面，再下面的字與色塊不記。[item]
  /// 還沒建（輪到才建，[CoverRevealSlot]）時傳回 null。
  static GroupedItemShape? measure(
    Element slot,
    Widget item, {
    required double visible,
  }) {
    final box = slot.renderObject;
    if (box is! RenderBox || !box.hasSize) return null;
    final rows = item is GroupedSection ? item.children : const <Widget>[];
    final rowSet = Set<Widget>.identity()..addAll(rows);
    final found = Map<Widget, RenderBox>.identity();
    var built = false;
    void visit(Element element) {
      final widget = element.widget;
      if (identical(widget, item)) built = true;
      if (rowSet.contains(widget)) {
        final rowBox = element.renderObject;
        if (rowBox is RenderBox && rowBox.hasSize) found[widget] = rowBox;
        return;
      }
      element.visitChildren(visit);
    }

    slot.visitChildren(visit);
    // 分組卡片在清單裡換成列各自排隊的版本，找得到每一列才算建好。
    Rect? card;
    if (item is GroupedSection) {
      if (found.length != rows.length || rows.isEmpty) return null;
      final first = _rectIn(found[rows.first]!, box);
      final last = _rectIn(found[rows.last]!, box);
      card = Rect.fromLTRB(first.left, first.top, first.right, last.bottom);
    } else if (!built) {
      return null;
    }
    final marks = <SkeletonShape>[];
    final width = box.size.width;
    void collect(RenderObject object) {
      if (object is RenderBox && object.hasSize && !object.size.isEmpty) {
        final rect = _rectIn(object, box);
        if (rect.bottom <= 0 ||
            rect.top >= box.size.height ||
            rect.top >= visible) {
          return;
        }
        switch (object) {
          case RenderParagraph():
            marks.addAll(_lines(object, box));
            return;
          case RenderImage():
            marks.add(SkeletonShape(rect, radius: _roundOf(rect, 12)));
            return;
          // 小塊的色塊（列首圖示方塊、開關、數值膠囊、步進鈕）整塊畫；大塊的
          // （卡片、分段控制的軌道）往裡面找字與小塊。
          case RenderDecoratedBox(:final Decoration decoration)
              when decoration is BoxDecoration &&
                  rect.width < width * 0.5 &&
                  (decoration.color?.a ?? 0) > 0:
            marks.add(
              SkeletonShape(
                rect,
                radius: decoration.shape == BoxShape.circle
                    ? BorderRadius.circular(rect.shortestSide / 2)
                    : decoration.borderRadius?.resolve(TextDirection.ltr) ??
                          BorderRadius.zero,
              ),
            );
            return;
          // 自己畫的小圖（風格縮圖）。
          case RenderCustomPaint(painter: CustomPainter())
              when rect.width < width * 0.5:
            marks.add(SkeletonShape(rect, radius: _roundOf(rect, 6)));
            return;
          case RenderPhysicalShape(:final color)
              when rect.width < width * 0.5 && color.a > 0:
            marks.add(SkeletonShape(rect, radius: _roundOf(rect, 999)));
            return;
          case RenderPhysicalModel(:final color, :final borderRadius)
              when rect.width < width * 0.5 && color.a > 0:
            marks.add(
              SkeletonShape(rect, radius: borderRadius ?? BorderRadius.zero),
            );
            return;
        }
      }
      object.visitChildren(collect);
    }

    box.visitChildren(collect);
    return GroupedItemShape(
      box.size.height,
      card: card,
      rowHeights: item is GroupedSection
          ? [for (final row in rows) found[row]!.size.height]
          : null,
      marks: marks,
    );
  }

  Map<String, Object?> toJson() => {
    'h': height,
    if (card case final card?) 'c': _rectToJson(card),
    if (rowHeights case final rows?) 'r': [for (final h in rows) _round(h)],
    'm': [
      for (final mark in marks)
        [..._rectToJson(mark.rect), mark.radius.topLeft.x],
    ],
  };

  static GroupedItemShape? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final height = (json['h'] as num?)?.toDouble();
    if (height == null) return null;
    final card = _rectFromJson(json['c']);
    final marks = <SkeletonShape>[];
    for (final mark in (json['m'] as List<Object?>? ?? const [])) {
      if (mark is! List<Object?> || mark.length != 5) return null;
      final rect = _rectFromJson(mark.sublist(0, 4));
      if (rect == null) return null;
      marks.add(
        SkeletonShape(
          rect,
          radius: BorderRadius.circular((mark[4] as num).toDouble()),
        ),
      );
    }
    final rows = json['r'];
    return GroupedItemShape(
      height,
      card: card,
      rowHeights: rows is List<Object?>
          ? [for (final h in rows) (h as num).toDouble()]
          : null,
      marks: marks,
    );
  }
}

/// 各頁上次換成內容時的樣子，以頁面的結構、寬度與字級區分；存在偏好設定
/// 裡，重開 App 後也照著畫。
abstract final class GroupedListLayouts {
  static const String _prefsKey = 'grouped_list_skeleton_v1';

  /// 最多記幾種版面；超過時丟掉最久沒更新的。
  static const int _capacity = 40;

  /// 照更新順序排，最後一個是最近更新的。
  static final Map<String, List<GroupedItemShape?>> _byPage = {};

  /// 每一頁編碼好的 JSON；和上次一樣就不重寫偏好設定。
  static final Map<String, String> _encoded = {};
  static SharedPreferences? _prefs;

  /// App 啟動時載入上次存的版面；之後量到的新版面也存到這裡。沒呼叫時
  /// （測試）只留在記憶體。
  static void load(SharedPreferences prefs) {
    _prefs = prefs;
    final saved = prefs.getString(_prefsKey);
    if (saved == null) return;
    try {
      final json = jsonDecode(saved) as Map<String, Object?>;
      for (final MapEntry(:key, :value) in json.entries) {
        if (value is! String) continue;
        final items = jsonDecode(value);
        if (items is! List<Object?>) continue;
        _byPage[key] = [
          for (final item in items) GroupedItemShape.fromJson(item),
        ];
        _encoded[key] = value;
      }
    } on Object {
      // 格式不對（舊版或損毀）就當作沒有紀錄。
      _byPage.clear();
      _encoded.clear();
    }
  }

  /// 同一個結構、寬度與字級才沿用：組的標題、有無右側按鈕與附註、列數與
  /// 每一列的元件種類有一樣變了就是另一個。種類取名稱的雜湊（FNV-1a），
  /// 上百列的組 key 也不會太長。
  static String keyOf(List<Widget> items, double width, TextScaler scaler) {
    final parts = [width.toStringAsFixed(0), scaler.scale(100).toString()];
    for (final item in items) {
      parts.add(switch (item) {
        GroupedSection(
          :final header,
          :final headerTrailing,
          :final children,
          :final footer,
        ) =>
          '$header/${headerTrailing != null}/${footer != null}/'
              '${children.length}/${_typesHash(children)}',
        _ => '${item.runtimeType}',
      });
    }
    return parts.join('|');
  }

  static String _typesHash(List<Widget> rows) {
    var hash = 0x811c9dc5;
    for (final row in rows) {
      for (final unit in '${_row(row).runtimeType};'.codeUnits) {
        hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
      }
    }
    return hash.toRadixString(36);
  }

  static List<GroupedItemShape?>? of(String key) => _byPage[key];

  static void remember(String key, List<GroupedItemShape?> shapes) {
    final encoded = jsonEncode([for (final shape in shapes) shape?.toJson()]);
    _byPage
      ..remove(key)
      ..[key] = shapes;
    final unchanged = _encoded.remove(key) == encoded;
    _encoded[key] = encoded;
    while (_byPage.length > _capacity) {
      _encoded.remove(_byPage.keys.first);
      _byPage.remove(_byPage.keys.first);
    }
    final prefs = _prefs;
    if (prefs == null || unchanged) return;
    unawaited(prefs.setString(_prefsKey, jsonEncode(_encoded)));
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
          for (final mark in shape.marks) {
            out.add(
              SkeletonShape(mark.rect.shift(offset), radius: mark.radius),
            );
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

const double _stepperHeight = NumberStepperRow.height;

/// 一行字的佔位條：和字號一樣高，以 [centreY] 為中線。
SkeletonShape _bar(double left, double centreY, double width, double height) =>
    SkeletonShape(Rect.fromLTWH(left, centreY - height / 2, width, height));

SkeletonShape _circle(Offset centre, double diameter) => SkeletonShape(
  Rect.fromCenter(center: centre, width: diameter, height: diameter),
  radius: BorderRadius.circular(diameter / 2),
);

/// 中文一個字約一個字號寬；最長到 [max]。
double _textWidth(int characters, double fontSize, double max) =>
    (characters * fontSize).clamp(fontSize * 2, max);

BorderRadius _roundOf(Rect rect, double max) {
  final half = rect.shortestSide / 2;
  return BorderRadius.circular(half < max ? half : max);
}

/// [object] 在 [ancestor] 裡的範圍（含中間的平移與縮放）。
Rect _rectIn(RenderBox object, RenderBox ancestor) => MatrixUtils.transformRect(
  object.getTransformTo(ancestor),
  Offset.zero & object.size,
);

/// 一段字每一行的佔位條：照實際排出來的寬度，高度是字號，對齊那一行的
/// 中線。圖示也是一個字，畫成和字形一樣大的圓角方塊。
List<SkeletonShape> _lines(RenderParagraph paragraph, RenderBox ancestor) {
  final text = paragraph.text.toPlainText(includeSemanticsLabels: false);
  if (text.trim().isEmpty) return const [];
  final fontSize = paragraph.textScaler.scale(
    paragraph.text.style?.fontSize ?? 14,
  );
  final lines = <Rect>[];
  for (final box in paragraph.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: text.length),
  )) {
    final rect = box.toRect();
    if (rect.top >= paragraph.size.height || rect.width <= 0) continue;
    final index = lines.indexWhere(
      (line) => (line.center.dy - rect.center.dy).abs() < rect.height / 2,
    );
    if (index < 0) {
      lines.add(rect);
    } else {
      lines[index] = lines[index].expandToInclude(rect);
    }
  }
  final transform = paragraph.getTransformTo(ancestor);
  final shapes = <SkeletonShape>[];
  for (final line in lines) {
    final height = fontSize < line.height ? fontSize : line.height;
    // 至少畫成方塊（單一個字或圖示），但不超出這段字的寬。
    final width = math.min(math.max(line.width, height), paragraph.size.width);
    shapes.add(
      SkeletonShape(
        MatrixUtils.transformRect(
          transform,
          Rect.fromLTWH(line.left, line.center.dy - height / 2, width, height),
        ),
        radius: BorderRadius.circular(height / 4),
      ),
    );
  }
  return shapes;
}

/// 穿過常見外框找出列本身（同 [groupedRowHasLeading]，另外穿過
/// [GroupedContent] 的內距）。
Widget _row(Widget widget) => switch (widget) {
  NumberStepperRowLike() => widget,
  GroupedContent(:final child) => _row(child),
  SwipeActions(:final child) => _row(child),
  KeyedSubtree(:final child) => _row(child),
  ProxyWidget(:final child) => _row(child),
  SingleChildRenderObjectWidget(:final child?) => _row(child),
  _ => widget,
};

String? _rowTitle(Widget row) => switch (row) {
  GroupedRow(:final title) => title,
  GroupedSwitchRow(:final title) => title,
  NumberStepperRowLike(:final label) => label,
  _ => null,
};

List<double> _rectToJson(Rect rect) => [
  for (final v in [rect.left, rect.top, rect.right, rect.bottom]) _round(v),
];

double _round(double v) => (v * 10).roundToDouble() / 10;

Rect? _rectFromJson(Object? json) {
  if (json is! List<Object?> || json.length != 4) return null;
  final [l, t, r, b] = [for (final v in json) (v as num).toDouble()];
  return Rect.fromLTRB(l, t, r, b);
}
