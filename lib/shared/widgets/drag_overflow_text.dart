import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'skeleton_text.dart';

/// 文字放得下時照原本的行數與排版；放不下時前幾行照常換行，最後一行接著排
/// 剩下的字，讀者可以左右拖動看完，不會自動跑馬燈，也不把卡片撐寬
/// （docs/design/components.md「過長文字」）。
///
/// 以實際欄寬、字級與系統的粗體、字距覆寫量測 [Text]：沒有限制行數的文字
/// 照常換行，不會被改成可拖。混合字樣的 [Text.rich] 放不下時整段排成一行拖。
/// 文字已經拖到邊上、還往邊外拖時，手勢讓給外層（列的滑動動作、換頁）。
/// 骨架照同一套排法畫（[dragOverflowCut]、[dragOverflowTailSpan]）。
class DragOverflowText extends StatelessWidget {
  const DragOverflowText({super.key, required this.child});

  final Text child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth || constraints.maxWidth <= 0) {
          return child;
        }

        final defaults = DefaultTextStyle.of(context);
        final maxLines = child.maxLines ?? defaults.maxLines;
        if (maxLines == null) return child;
        final textAlign =
            child.textAlign ?? defaults.textAlign ?? TextAlign.start;
        final painter = TextPainter(
          text: skeletonTextSpan(
            context,
            text: child.data,
            child: child.textSpan,
            style: child.style,
          ),
          textAlign: textAlign,
          textDirection: child.textDirection ?? Directionality.of(context),
          textScaler: child.textScaler ?? MediaQuery.textScalerOf(context),
          locale: child.locale ?? Localizations.maybeLocaleOf(context),
          strutStyle: child.strutStyle,
          textHeightBehavior:
              child.textHeightBehavior ?? defaults.textHeightBehavior,
          textWidthBasis: child.textWidthBasis ?? defaults.textWidthBasis,
          maxLines: maxLines,
          ellipsis: '…',
        )..layout(maxWidth: constraints.maxWidth);
        final exceeds = painter.didExceedMaxLines;
        final height = painter.height;
        final data = child.data;
        final cut = exceeds && data != null ? dragOverflowCut(painter) : 0;
        painter.dispose();
        if (!exceeds) return child;

        Text text(InlineSpan span, {int? maxLines, bool softWrap = true}) =>
            Text.rich(
              span,
              style: child.style,
              strutStyle: child.strutStyle,
              textAlign: child.textAlign,
              textDirection: child.textDirection,
              locale: child.locale,
              softWrap: softWrap,
              overflow: TextOverflow.clip,
              textScaler: child.textScaler,
              maxLines: maxLines,
              textWidthBasis: child.textWidthBasis,
              textHeightBehavior: child.textHeightBehavior,
              selectionColor: child.selectionColor,
            );

        final tail = dragOverflowTailSpan(
          data == null ? child.textSpan! : TextSpan(text: data.substring(cut)),
        );
        // 高度維持原本幾行的高，書卡、分組清單與漫畫換章分隔的上下內容
        // 不移位；行高取整差的零點幾像素裁掉。
        return Semantics(
          label: child.semanticsLabel ?? data ?? child.textSpan!.toPlainText(),
          excludeSemantics: true,
          child: SizedBox(
            height: height,
            child: ClipRect(
              child: OverflowBox(
                alignment: AlignmentDirectional.topStart,
                maxHeight: double.infinity,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (cut > 0)
                      text(
                        TextSpan(text: _trimBreak(data!.substring(0, cut))),
                        maxLines: maxLines - 1,
                      ),
                    _DragLine(
                      // 清單重用卡片時，新的字不沿用上一段的橫向位置。
                      key: ValueKey(tail.toPlainText()),
                      width: constraints.maxWidth,
                      child: text(tail, softWrap: false),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 可拖的那一行：橫向捲動，但已經在邊上、還往邊外拖時不接手勢。
class _DragLine extends StatefulWidget {
  const _DragLine({super.key, required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  State<_DragLine> createState() => _DragLineState();
}

class _DragLineState extends State<_DragLine> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _move(double delta) {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    _controller.jumpTo(
      (position.pixels - delta).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
  }

  void _settle(DragEndDetails details) {
    if (!_controller.hasClients) return;
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() < kMinFlingVelocity) return;
    final position = _controller.position;
    _controller.animateTo(
      (position.pixels - velocity * 0.25).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 300),
      curve: Curves.decelerate,
    );
  }

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      gestures: {
        _EdgeYieldingDragRecognizer:
            GestureRecognizerFactoryWithHandlers<_EdgeYieldingDragRecognizer>(
              () => _EdgeYieldingDragRecognizer(_controller),
              (recognizer) => recognizer
                ..onUpdate = ((details) => _move(details.delta.dx))
                ..onEnd = _settle,
            ),
      },
      child: SingleChildScrollView(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: widget.width),
          child: widget.child,
        ),
      ),
    );
  }
}

/// 橫向拖動，但文字已經拖到左邊、還往右拖（或在右邊往左拖）時不接，讓外層
/// 的橫向手勢（列的滑動動作、換頁）贏。
class _EdgeYieldingDragRecognizer extends HorizontalDragGestureRecognizer {
  _EdgeYieldingDragRecognizer(this._controller);

  final ScrollController _controller;
  final Map<int, Offset> _starts = {};
  double _dx = 0;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _starts[event.pointer] = event.position;
    _dx = 0;
    super.addAllowedPointer(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    final start = _starts[event.pointer];
    if (start != null && event is PointerMoveEvent) {
      _dx = event.position.dx - start.dx;
    }
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      _starts.remove(event.pointer);
    }
    super.handleEvent(event);
  }

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) {
    if (!super.hasSufficientGlobalDistanceToAccept(
      pointerDeviceKind,
      deviceTouchSlop,
    )) {
      return false;
    }
    if (!_controller.hasClients) return true;
    final position = _controller.position;
    if (_dx > 0 && position.pixels <= position.minScrollExtent) return false;
    if (_dx < 0 && position.pixels >= position.maxScrollExtent) return false;
    return true;
  }
}

/// [painter]（照 [Text] 的行數上限排好、放不下）最後一行從第幾個字開始：
/// 那一行起的字都排在可拖的那一行。只有一行時是 0。
int dragOverflowCut(TextPainter painter) {
  final lines = painter.computeLineMetrics();
  if (lines.length <= 1) return 0;
  final last = lines.last;
  return painter
      .getLineBoundary(
        painter.getPositionForOffset(
          Offset(0, last.baseline - last.ascent + last.height / 2),
        ),
      )
      .start;
}

/// 可拖的那一行要排的字：換行符號換成空白，整段排在同一行；每一段的字樣
/// 照舊。
InlineSpan dragOverflowTailSpan(InlineSpan span) => switch (span) {
  TextSpan() when span.runtimeType == TextSpan => TextSpan(
    text: span.text?.replaceAll('\n', ' '),
    children: span.children?.map(dragOverflowTailSpan).toList(),
    style: span.style,
    recognizer: span.recognizer,
    mouseCursor: span.mouseCursor,
    onEnter: span.onEnter,
    onExit: span.onExit,
    semanticsLabel: span.semanticsLabel,
    locale: span.locale,
    spellOut: span.spellOut,
  ),
  _ => span,
};

/// 前幾行結尾的換行已經由分行表示，留著會多排一個空行。
String _trimBreak(String head) =>
    head.endsWith('\n') ? head.substring(0, head.length - 1) : head;
