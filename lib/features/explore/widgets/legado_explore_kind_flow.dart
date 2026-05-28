import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:reader/core/models/source/explore_kind.dart';

/// A Flutter-side flexbox approximation for Legado discover categories.
///
/// Flutter's `Wrap` cannot represent `layout_wrapBefore`,
/// `layout_flexBasisPercent`, `layout_flexGrow`, `layout_flexShrink`, or
/// per-child cross-axis alignment. This render object keeps the discover page
/// closer to how mature Legado sources expect category buttons to flow.
class LegadoExploreKindFlow extends MultiChildRenderObjectWidget {
  final List<FlexChildStyle> styles;
  final double horizontalSpacing;
  final double verticalSpacing;

  const LegadoExploreKindFlow({
    super.key,
    required this.styles,
    required super.children,
    this.horizontalSpacing = 8,
    this.verticalSpacing = 8,
  });

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderLegadoExploreKindFlow(
      styles: styles,
      horizontalSpacing: horizontalSpacing,
      verticalSpacing: verticalSpacing,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    final flowRenderObject = renderObject as _RenderLegadoExploreKindFlow;
    flowRenderObject
      ..styles = styles
      ..horizontalSpacing = horizontalSpacing
      ..verticalSpacing = verticalSpacing;
  }
}

class _LegadoExploreKindParentData extends ContainerBoxParentData<RenderBox> {}

class _FlexItemLayout {
  _FlexItemLayout({
    required this.child,
    required this.style,
    required this.baseWidth,
  });

  final RenderBox child;
  final FlexChildStyle style;
  final double baseWidth;
  double allocatedWidth = 0;
  double actualWidth = 0;
  double actualHeight = 0;
}

class _RenderLegadoExploreKindFlow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _LegadoExploreKindParentData>,
        RenderBoxContainerDefaultsMixin<
          RenderBox,
          _LegadoExploreKindParentData
        > {
  _RenderLegadoExploreKindFlow({
    required List<FlexChildStyle> styles,
    required double horizontalSpacing,
    required double verticalSpacing,
  }) : _styles = styles,
       _horizontalSpacing = horizontalSpacing,
       _verticalSpacing = verticalSpacing;

  List<FlexChildStyle> _styles;
  double _horizontalSpacing;
  double _verticalSpacing;

  List<FlexChildStyle> get styles => _styles;
  set styles(List<FlexChildStyle> value) {
    if (_styles == value) {
      return;
    }
    _styles = value;
    markNeedsLayout();
  }

  double get horizontalSpacing => _horizontalSpacing;
  set horizontalSpacing(double value) {
    if (_horizontalSpacing == value) {
      return;
    }
    _horizontalSpacing = value;
    markNeedsLayout();
  }

  double get verticalSpacing => _verticalSpacing;
  set verticalSpacing(double value) {
    if (_verticalSpacing == value) {
      return;
    }
    _verticalSpacing = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _LegadoExploreKindParentData) {
      child.parentData = _LegadoExploreKindParentData();
    }
  }

  @override
  void performLayout() {
    final width = _resolveLayoutWidth(constraints);
    final rows = _buildRows(width);
    var y = 0.0;

    for (var index = 0; index < rows.length; index++) {
      y += _layoutRow(rows[index], width, y);
      if (index < rows.length - 1) {
        y += verticalSpacing;
      }
    }

    size = constraints.constrain(Size(width, y));
  }

  double _resolveLayoutWidth(BoxConstraints constraints) {
    if (constraints.maxWidth.isFinite) {
      return constraints.maxWidth;
    }
    if (constraints.minWidth.isFinite && constraints.minWidth > 0) {
      return constraints.minWidth;
    }
    return 320;
  }

  FlexChildStyle _styleAt(int index) {
    if (index >= 0 && index < styles.length) {
      return styles[index];
    }
    return FlexChildStyle.defaultStyle;
  }

  List<List<_FlexItemLayout>> _buildRows(double maxWidth) {
    final rows = <List<_FlexItemLayout>>[];
    var currentRow = <_FlexItemLayout>[];
    var currentRowWidth = 0.0;
    var child = firstChild;
    var index = 0;

    while (child != null) {
      final parentData = child.parentData! as _LegadoExploreKindParentData;
      final style = _styleAt(index);
      final baseWidth = _measureBaseWidth(child, style, maxWidth);
      final nextWidth =
          currentRowWidth +
          (currentRow.isEmpty ? 0 : horizontalSpacing) +
          baseWidth;

      if (style.layoutWrapBefore && currentRow.isNotEmpty) {
        rows.add(currentRow);
        currentRow = <_FlexItemLayout>[];
        currentRowWidth = 0;
      } else if (currentRow.isNotEmpty && nextWidth > maxWidth) {
        rows.add(currentRow);
        currentRow = <_FlexItemLayout>[];
        currentRowWidth = 0;
      }

      currentRow.add(
        _FlexItemLayout(child: child, style: style, baseWidth: baseWidth),
      );
      currentRowWidth +=
          (currentRow.length == 1 ? 0 : horizontalSpacing) + baseWidth;

      child = parentData.nextSibling;
      index++;
    }

    if (currentRow.isNotEmpty) {
      rows.add(currentRow);
    }

    return rows;
  }

  double _measureBaseWidth(
    RenderBox child,
    FlexChildStyle style,
    double maxWidth,
  ) {
    final basisPercent = style.layoutFlexBasisPercent;
    if (basisPercent >= 0) {
      final normalizedBasis = basisPercent.clamp(0, 1).toDouble();
      final compensatedGap = horizontalSpacing * (1 - normalizedBasis);
      return (maxWidth * normalizedBasis - compensatedGap)
          .clamp(0, maxWidth)
          .toDouble();
    }

    child.layout(BoxConstraints(maxWidth: maxWidth), parentUsesSize: true);
    return child.size.width.clamp(0, maxWidth).toDouble();
  }

  double _layoutRow(List<_FlexItemLayout> row, double maxWidth, double y) {
    final spacingWidth = horizontalSpacing * math.max(0, row.length - 1);
    final baseWidth = row.fold<double>(
      0,
      (total, item) => total + item.baseWidth,
    );
    final remainingWidth = maxWidth - baseWidth - spacingWidth;

    if (remainingWidth > 0) {
      final growTotal = row.fold<double>(
        0,
        (total, item) => total + math.max(0, item.style.layoutFlexGrow),
      );
      for (final item in row) {
        final grow = math.max(0, item.style.layoutFlexGrow);
        item.allocatedWidth =
            item.baseWidth +
            (growTotal > 0 ? remainingWidth * grow / growTotal : 0);
      }
    } else if (remainingWidth < 0) {
      final shrinkTotal = row.fold<double>(
        0,
        (total, item) => total + math.max(0, item.style.layoutFlexShrink),
      );
      for (final item in row) {
        final shrink = math.max(0, item.style.layoutFlexShrink);
        item.allocatedWidth = math.max(
          0,
          item.baseWidth +
              (shrinkTotal > 0 ? remainingWidth * shrink / shrinkTotal : 0),
        );
      }
    } else {
      for (final item in row) {
        item.allocatedWidth = item.baseWidth;
      }
    }

    var rowHeight = 0.0;
    for (final item in row) {
      final shouldConstrainWidth =
          item.style.layoutFlexBasisPercent >= 0 ||
          item.style.layoutFlexGrow > 0 ||
          remainingWidth < 0;
      final childConstraints =
          shouldConstrainWidth
              ? BoxConstraints.tightFor(width: item.allocatedWidth)
              : BoxConstraints(maxWidth: item.allocatedWidth);
      item.child.layout(childConstraints, parentUsesSize: true);
      item.actualWidth =
          shouldConstrainWidth ? item.allocatedWidth : item.child.size.width;
      item.actualHeight = item.child.size.height;
      rowHeight = math.max(rowHeight, item.actualHeight);
    }

    var x = 0.0;
    for (final item in row) {
      if (item.style.layoutAlignSelf == 'stretch' &&
          item.actualHeight < rowHeight) {
        item.child.layout(
          BoxConstraints.tightFor(width: item.actualWidth, height: rowHeight),
          parentUsesSize: true,
        );
        item.actualHeight = item.child.size.height;
      }

      final parentData = item.child.parentData! as _LegadoExploreKindParentData;
      parentData.offset = Offset(x, y + _crossAxisOffset(item, rowHeight));
      x += item.actualWidth + horizontalSpacing;
    }

    return rowHeight;
  }

  double _crossAxisOffset(_FlexItemLayout item, double rowHeight) {
    final freeHeight = math.max(0, rowHeight - item.actualHeight).toDouble();
    switch (item.style.layoutAlignSelf) {
      case 'flex_end':
        return freeHeight;
      case 'center':
        return freeHeight / 2;
      case 'baseline':
      case 'stretch':
      case 'flex_start':
      case 'auto':
      default:
        return 0;
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return defaultHitTestChildren(result, position: position);
  }
}
