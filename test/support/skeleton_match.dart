// 骨架和換上的內容對不對得上（ADR 0029）：骨架畫的每一塊（字條、圖示、
// 色塊、卡片）在內容裡都有同一個位置、同樣大小的一塊，反過來也一樣。
//
// 骨架從畫面上的 [SkeletonShapes] 讀出它畫的形狀；內容從排好的畫面量：每一
// 行字一條（和字一樣寬、字號一樣高，對著那一行的中線），圖片、自己畫的
// 小圖與小塊的色塊（圖示方塊、開關、數值膠囊、步進鈕）整塊，分組卡片照
// 卡片的範圍。
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/shared/widgets/glass_segmented.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';

/// 一個畫面上的形狀，全域座標。
class SkeletonLayout {
  const SkeletonLayout({required this.marks, required this.cards});

  final List<Rect> marks;
  final List<Rect> cards;
}

/// [skeleton] 這個 [SkeletonShapes] 畫的形狀。
SkeletonLayout skeletonLayoutOf(WidgetTester tester, Finder skeleton) {
  final element = tester.element(skeleton);
  final box = element.renderObject! as RenderBox;
  final origin = box.localToGlobal(Offset.zero);
  final shapes = (element.widget as SkeletonShapes).shapes(box.size);
  return SkeletonLayout(
    marks: [
      for (final shape in shapes)
        if (shape.fill == null) shape.rect.shift(origin),
    ],
    cards: [
      for (final shape in shapes)
        if (shape.fill != null) shape.rect.shift(origin),
    ],
  );
}

/// [content] 底下排好的畫面量出來的形狀。
SkeletonLayout contentLayoutOf(WidgetTester tester, Finder content) {
  final root = tester.renderObject<RenderBox>(content);
  final width = root.size.width;
  final marks = <Rect>[];
  // 分段控制整條軌道是一塊（和閱讀器面板的骨架一樣）。
  final segmented = [
    for (final element
        in find
            .descendant(
              of: content,
              matching: find.byWidgetPredicate(
                (widget) => widget is GlassSegmented,
              ),
            )
            .evaluate())
      tester.getRect(find.byWidget(element.widget)),
  ];
  final buttons = [
    for (final element
        in find
            .descendant(
              of: content,
              matching: find.byWidgetPredicate(
                (widget) => widget is ButtonStyleButton,
              ),
            )
            .evaluate())
      tester.getRect(find.byWidget(element.widget)),
  ];
  void collect(RenderObject object) {
    if (object is RenderBox && object.hasSize && !object.size.isEmpty) {
      final rect = MatrixUtils.transformRect(
        object.getTransformTo(null),
        Offset.zero & object.size,
      );
      if (segmented.any((track) => _near(track, rect))) {
        marks.add(rect);
        return;
      }
      switch (object) {
        case RenderParagraph():
          marks.addAll(_lines(object));
          return;
        case RenderImage():
          marks.add(rect);
          return;
        // 小塊的色塊整塊畫；大塊的（卡片、分段控制的軌道）往裡面找。
        case RenderDecoratedBox(:final Decoration decoration)
            when decoration is BoxDecoration &&
                rect.width < width * 0.5 &&
                (decoration.color?.a ?? 0) > 0:
          marks.add(rect);
          return;
        // 文字按鈕按下時的水波紋那一層看不到，不算。
        case RenderCustomPaint(painter: CustomPainter())
            when rect.width < width * 0.5 &&
                !buttons.any((button) => _near(button, rect)):
          marks.add(rect);
          return;
        case RenderPhysicalShape(:final color)
            when rect.width < width * 0.5 && color.a > 0:
          marks.add(rect);
          return;
        case RenderPhysicalModel(:final color)
            when rect.width < width * 0.5 && color.a > 0:
          marks.add(rect);
          return;
      }
    }
    object.visitChildren(collect);
  }

  root.visitChildren(collect);
  final cards = [
    for (final element
        in find
            .descendant(of: content, matching: find.byType(GroupedSection))
            .evaluate())
      for (final clip
          in find
              .descendant(
                of: find.byWidget(element.widget),
                matching: find.byType(ClipRRect),
              )
              .evaluate()
              .take(1))
        tester.getRect(find.byWidget(clip.widget)),
  ];
  return SkeletonLayout(marks: marks, cards: cards);
}

bool _near(Rect a, Rect b, [double tolerance = 0.5]) =>
    (a.left - b.left).abs() <= tolerance &&
    (a.top - b.top).abs() <= tolerance &&
    (a.right - b.right).abs() <= tolerance &&
    (a.bottom - b.bottom).abs() <= tolerance;

List<Rect> _lines(RenderParagraph paragraph) {
  final text = paragraph.text.toPlainText(includeSemanticsLabels: false);
  if (text.trim().isEmpty) return const [];
  final fontSize = paragraph.textScaler.scale(
    paragraph.text.style?.fontSize ?? 14,
  );
  // 每一行：左右取所有字的範圍，上下取最寬的那一段字。一行裡換了字型的
  // 那一小段（例如刪節號「…」來自另一個字型）字框比較高，併進去會把整行
  // 的中線拉偏，但畫面上的字並沒有跟著動。
  final lines = <({Rect all, Rect widest})>[];
  for (final box in paragraph.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: text.length),
  )) {
    final rect = box.toRect();
    if (rect.top >= paragraph.size.height || rect.width <= 0) continue;
    final index = lines.indexWhere(
      (line) => (line.all.center.dy - rect.center.dy).abs() < rect.height / 2,
    );
    if (index < 0) {
      lines.add((all: rect, widest: rect));
    } else {
      final line = lines[index];
      lines[index] = (
        all: line.all.expandToInclude(rect),
        widest: rect.width > line.widest.width ? rect : line.widest,
      );
    }
  }
  final transform = paragraph.getTransformTo(null);
  return [
    for (final (:all, :widest) in lines)
      MatrixUtils.transformRect(transform, () {
        final height = math.min(fontSize, widest.height);
        final width = math.min(
          math.max(all.width, height),
          paragraph.size.width,
        );
        return Rect.fromLTWH(
          all.left,
          widest.center.dy - height / 2,
          width,
          height,
        );
      }()),
  ];
}

/// 兩邊在 [visible] 裡的形狀逐一配對，傳回對不上的（空的就是一樣）。
List<String> skeletonMismatches(
  SkeletonLayout skeleton,
  SkeletonLayout content, {
  required Rect visible,
  double tolerance = 0.5,
}) {
  bool same(Rect a, Rect b) => _near(a, b, tolerance);
  List<Rect> inView(List<Rect> rects) => [
    for (final rect in rects)
      if (visible.contains(rect.topLeft) && visible.contains(rect.bottomRight))
        rect,
  ];
  String show(Rect r) =>
      '(${r.left.toStringAsFixed(1)}, ${r.top.toStringAsFixed(1)}) '
      '${r.width.toStringAsFixed(1)}×${r.height.toStringAsFixed(1)}';
  final out = <String>[];
  void pair(String kind, List<Rect> drawn, List<Rect> real) {
    final left = inView(real);
    for (final rect in inView(drawn)) {
      final index = left.indexWhere((other) => same(rect, other));
      if (index < 0) {
        out.add('骨架多出$kind ${show(rect)}');
      } else {
        left.removeAt(index);
      }
    }
    for (final rect in left) {
      out.add('內容有、骨架沒有的$kind ${show(rect)}');
    }
  }

  pair('形狀', skeleton.marks, content.marks);
  pair('卡片', skeleton.cards, content.cards);
  return out;
}
