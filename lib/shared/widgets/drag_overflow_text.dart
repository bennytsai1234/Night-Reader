import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'skeleton_text.dart';
import 'ui_text.dart';

/// 文字放得下時照原本的行數與排版；放不下時前幾行照常換行，最後一行接著排
/// 剩下的字，讀者可以左右拖動看完，不會自動跑馬燈，也不把卡片撐寬
/// （docs/design/components.md「過長文字」）。
///
/// 以實際欄寬、字級與系統的粗體、字距覆寫量測 [Text]：沒有限制行數的文字
/// 照常換行，不會被改成可拖。混合字樣的 [Text.rich] 放不下時整段排成一行拖。
/// 文字已經拖到邊上、還往邊外拖時，手勢讓給外層（列的滑動動作、換頁）；
/// 手勢途中才拖到邊上時，剩下的位移接著拖外層的分頁，放開後停到整頁。
/// 外層分頁已經在該方向的邊界時，手勢留在字上，同一次手勢反向可以拉回。
/// 骨架照同一套排法畫（[dragOverflowCut]、[dragOverflowTailSpan]）。
class DragOverflowText extends StatelessWidget {
  const DragOverflowText({super.key, required this.child});

  final Text child;

  @override
  Widget build(BuildContext context) {
    final child = this.child is UiText
        ? (this.child as UiText).displayText(context)
        : this.child;
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

/// 可拖的那一行：橫向捲動；已經在邊上、還往邊外拖時不接手勢。手勢途中才
/// 拖到邊上時，剩下的位移接著拖外層的水平捲動（主頁分頁），放開後停到整頁。
class _DragLine extends StatefulWidget {
  const _DragLine({super.key, required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  State<_DragLine> createState() => _DragLineState();
}

class _DragLineState extends State<_DragLine> {
  final _controller = ScrollController();

  /// 外層的分頁捲動（主頁的 [PageView]）；第一次拖到邊界時才找。
  ScrollableState? _pagerState;
  ScrollPosition? _pagerPosition;

  /// 已經把剩下的位移交給外層分頁的那次拖曳。用分頁自己的拖曳活動，
  /// 拖曳期間才不會被 `jumpTo` 的吸附拉回去；放開後由分頁的 physics
  /// 停到整頁。
  Drag? _pagerDrag;

  /// 這一次手勢已經把剩下的位移交給外層；到放開前都給外層，不拉回字。
  bool _handedOff = false;

  /// 目前這條手勢的辨識器；系統取消時它會記下來。
  _EdgeYieldingDragRecognizer? _recognizer;

  @override
  void dispose() {
    if (_pagerAlive) _pagerDrag?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// 接手的外層分頁還在，而且沒有被換掉（鎖住分頁時 Flutter 會換一個
  /// 新的 ScrollPosition）。
  bool get _pagerAlive {
    final state = _pagerState;
    if (state == null || !state.mounted) return false;
    final position = state.position;
    return identical(position, _pagerPosition) && position.hasContentDimensions;
  }

  void _move(DragUpdateDetails details) {
    if (!_controller.hasClients) return;
    if (_handedOff) {
      if (!_pagerAlive) {
        _endHandoff();
        return;
      }
      _pagerDrag?.update(details);
      return;
    }
    final position = _controller.position;
    final target = (position.pixels - details.delta.dx).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    // 字吃掉的手指位移；剩下的是拖到邊界後多出來的，交給外層。
    final consumed = position.pixels - target;
    final remaining = details.delta.dx - consumed;
    if (target != position.pixels) _controller.jumpTo(target);
    if (remaining.abs() > 0.01) _startHandoff(details, remaining);
  }

  /// 找最近的外層分頁：往上會先經過書架的直向清單，跳過它。
  ScrollableState? _findPager() {
    ScrollableState? found;
    context.visitAncestorElements((element) {
      final widget = element.widget;
      if (widget is Scrollable &&
          axisDirectionToAxis(widget.axisDirection) == Axis.horizontal) {
        final state = (element as StatefulElement).state;
        if (state is ScrollableState && _isPaged(state.position.physics)) {
          found = state;
          return false;
        }
      }
      return true;
    });
    return found;
  }

  /// 一次拖動會經過好幾層捲動物件；只有分頁那種才接手剩下的位移。
  /// 分頁列鎖住（整頁編輯）時不接手。
  bool _isPaged(ScrollPhysics physics) {
    var paged = false;
    ScrollPhysics? current = physics;
    while (current != null) {
      if (current is NeverScrollableScrollPhysics) return false;
      if (current is PageScrollPhysics) paged = true;
      current = current.parent;
    }
    return paged;
  }

  /// 書名已經在邊界、外層分頁還能往這個方向動時才讓給外層；分頁也在
  /// 邊界（只有一頁或末頁）時留下來，同一次手勢反向才拉得回字。
  bool _pagerCanMove(double dx) {
    final state = _findPager();
    // 沒有可接手的分頁（例如列的滑動動作）：照舊在邊界讓給外層。
    if (state == null || !state.mounted) return true;
    final position = state.position;
    if (position is! ScrollPositionWithSingleContext ||
        !position.hasContentDimensions) {
      return true;
    }
    final target = (position.pixels - dx).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    return (target - position.pixels).abs() > 0.01;
  }

  /// 開始接手：分頁要真的能往這個方向動，才把拖曳交出去。分頁已經在
  /// 邊界時不接手，同一次手勢反向才拉得回字。
  void _startHandoff(DragUpdateDetails details, double remaining) {
    final state = _pagerState ??= _findPager();
    if (state == null || !state.mounted) return;
    final position = state.position;
    if (position is! ScrollPositionWithSingleContext ||
        !position.hasContentDimensions) {
      return;
    }
    final target = (position.pixels - remaining).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((target - position.pixels).abs() < 0.01) return;

    _pagerPosition = position;
    _pagerDrag =
        position.drag(
          DragStartDetails(
            globalPosition: details.globalPosition,
            localPosition: details.localPosition,
            sourceTimeStamp: details.sourceTimeStamp,
          ),
          () {},
        )..update(
          DragUpdateDetails(
            globalPosition: details.globalPosition,
            localPosition: details.localPosition,
            delta: Offset(remaining, 0),
            primaryDelta: remaining,
            sourceTimeStamp: details.sourceTimeStamp,
          ),
        );
    _handedOff = true;
  }

  void _settle(DragEndDetails details) {
    // 系統取消（例如來電、手勢被搶走）不該照最後的速度甩到下一頁。
    if (_recognizer?.cancelled ?? false) {
      _cancel();
      return;
    }
    final drag = _pagerDrag;
    if (_handedOff && drag != null) {
      if (_pagerAlive) drag.end(details);
      _endHandoff();
      return;
    }
    _endHandoff();
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

  void _cancel() {
    if (_handedOff && _pagerAlive) _pagerDrag?.cancel();
    _endHandoff();
  }

  void _endHandoff() {
    _handedOff = false;
    _pagerDrag = null;
    _pagerState = null;
    _pagerPosition = null;
  }

  @override
  Widget build(BuildContext context) {
    final gestureSettings = MediaQuery.maybeGestureSettingsOf(context);
    return RawGestureDetector(
      gestures: {
        _EdgeYieldingDragRecognizer:
            GestureRecognizerFactoryWithHandlers<_EdgeYieldingDragRecognizer>(
              () {
                final recognizer = _EdgeYieldingDragRecognizer(
                  _controller,
                  canHandOff: _pagerCanMove,
                );
                _recognizer = recognizer;
                return recognizer;
              },
              (recognizer) => recognizer
                ..gestureSettings = gestureSettings
                ..onStart = ((_) => _endHandoff())
                ..onUpdate = _move
                ..onEnd = _settle
                ..onCancel = _cancel,
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
  _EdgeYieldingDragRecognizer(this._controller, {this.canHandOff});

  final ScrollController _controller;

  /// 外層分頁能不能往手指的方向動；不能時書名留在自己手上。
  final bool Function(double dx)? canHandOff;

  final Map<int, Offset> _starts = {};
  double _dx = 0;

  /// 這一條手勢被系統取消（不是使用者放開）；放開時不能照速度甩頁。
  bool cancelled = false;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _starts[event.pointer] = event.position;
    _dx = 0;
    cancelled = false;
    super.addAllowedPointer(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    final start = _starts[event.pointer];
    if (start != null && event is PointerMoveEvent) {
      _dx = event.position.dx - start.dx;
    }
    if (event is PointerCancelEvent) cancelled = true;
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
    final atStart = _dx > 0 && position.pixels <= position.minScrollExtent;
    final atEnd = _dx < 0 && position.pixels >= position.maxScrollExtent;
    if ((atStart || atEnd) && (canHandOff?.call(_dx) ?? true)) return false;
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
