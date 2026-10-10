import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/features/about/external_url_launcher.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/reader_v2/hybrid/overlay/selection_service.dart';

/// 正文選字的反白、兩端把手與選單。
///
/// 疊在 [child]（正文與它的點擊／長按手勢）之上、作為兄弟節點：按把手或
/// 選單不會落到正文的點擊層而被當成「取消選取」。座標一律是正文 viewport
/// 本地座標，幾何換算由閱讀畫面提供。
final class ReaderTextSelectionLayer extends StatefulWidget {
  const ReaderTextSelectionLayer({
    super.key,
    required this.selection,
    required this.repaint,
    required this.boxesFor,
    required this.caretAt,
    required this.highlightColor,
    required this.child,
  });

  final SelectionService selection;

  /// 正文捲動時重算框位置。
  final Listenable repaint;

  /// 選取範圍在 viewport 上的字形框，每條視覺行一個。
  final List<HybridLineBox> Function(ReaderTextSelection selection) boxesFor;

  /// viewport 上一點在選取段落內最近的游標位置（章內 offset）。
  final int? Function(ReaderTextSelection selection, Offset point) caretAt;

  final Color highlightColor;
  final Widget child;

  @override
  State<ReaderTextSelectionLayer> createState() =>
      _ReaderTextSelectionLayerState();
}

class _ReaderTextSelectionLayerState extends State<ReaderTextSelectionLayer> {
  static const double _selectionAlpha = 0.35;
  static const String _webSearchUrl = 'https://www.google.com/search?q=';

  final ProcessTextService _processText = DefaultProcessTextService();
  List<ProcessTextAction> _processTextActions = const <ProcessTextAction>[];
  SelectionEdge? _dragEdge;
  Offset? _dragPoint;

  @override
  void initState() {
    super.initState();
    // 與 EditableText 相同：系統可處理文字的 App（翻譯、字典…）只查一次。
    unawaited(
      _processText.queryTextActions().then((actions) {
        if (mounted) setState(() => _processTextActions = actions);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        widget.child,
        ListenableBuilder(
          listenable: Listenable.merge(<Listenable>[
            widget.selection,
            widget.repaint,
          ]),
          builder: (context, _) {
            final selection = widget.selection.selection;
            if (selection == null) return const SizedBox.shrink();
            final boxes = widget.boxesFor(selection);
            if (boxes.isEmpty) return const SizedBox.shrink();
            return Stack(
              fit: StackFit.expand,
              children: <Widget>[
                IgnorePointer(
                  child: CustomPaint(
                    painter: _SelectionPainter(
                      boxes: boxes,
                      color: widget.highlightColor.withValues(
                        alpha: _selectionAlpha,
                      ),
                    ),
                  ),
                ),
                _buildHandle(boxes.first, SelectionEdge.start),
                _buildHandle(boxes.last, SelectionEdge.end),
                if (_dragEdge == null) _buildToolbar(context, selection, boxes),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildHandle(HybridLineBox box, SelectionEdge edge) {
    final controls = materialTextSelectionHandleControls;
    final type = edge == SelectionEdge.start
        ? TextSelectionHandleType.left
        : TextSelectionHandleType.right;
    final lineHeight = box.bottom - box.top;
    final caretX = edge == SelectionEdge.start ? box.left : box.right;
    final anchor = controls.getHandleAnchor(type, lineHeight);
    final size = controls.getHandleSize(lineHeight);
    // 把手本體只有 22dp，四周補到最小觸控尺寸。
    final pad = math.max(0.0, (kMinInteractiveDimension - size.width) / 2);
    return Positioned(
      key: ValueKey<SelectionEdge>(edge),
      left: caretX - anchor.dx - pad,
      top: box.bottom - anchor.dy - pad,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => setState(() {
          _dragEdge = edge;
          _dragPoint = Offset(caretX, (box.top + box.bottom) / 2);
        }),
        onPanUpdate: _handleDragUpdate,
        onPanEnd: (_) => _endDrag(),
        onPanCancel: _endDrag,
        child: Padding(
          padding: EdgeInsets.all(pad),
          child: Theme(
            data: Theme.of(context).copyWith(
              textSelectionTheme: TextSelectionThemeData(
                selectionHandleColor: widget.highlightColor,
              ),
            ),
            child: Builder(
              builder: (context) =>
                  controls.buildHandle(context, type, lineHeight),
            ),
          ),
        ),
      ),
    );
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    final selection = widget.selection.selection;
    final edge = _dragEdge;
    final point = _dragPoint;
    if (selection == null || edge == null || point == null) return;
    final next = point + details.delta;
    _dragPoint = next;
    final offset = widget.caretAt(selection, next);
    if (offset == null) return;
    final moved = selection.moveEdge(edge, offset);
    _dragEdge = moved.edge;
    if (moved.selection.range == selection.range) return;
    widget.selection.select(moved.selection);
    unawaited(HapticFeedback.selectionClick());
  }

  void _endDrag() {
    if (!mounted) return;
    setState(() {
      _dragEdge = null;
      _dragPoint = null;
    });
  }

  Widget _buildToolbar(
    BuildContext context,
    ReaderTextSelection selection,
    List<HybridLineBox> boxes,
  ) {
    final left = boxes.map((box) => box.left).reduce(math.min);
    final right = boxes.map((box) => box.right).reduce(math.max);
    final centerX = (left + right) / 2;
    final last = boxes.last;
    final handleHeight = materialTextSelectionHandleControls
        .getHandleSize(last.bottom - last.top)
        .height;
    final items = <ContextMenuButtonItem>[
      ContextMenuButtonItem(
        label: '複製',
        onPressed: () => unawaited(_copy(selection)),
      ),
      ContextMenuButtonItem(
        label: '搜尋',
        onPressed: () => unawaited(_webSearch(selection)),
      ),
      for (final action in _processTextActions)
        ContextMenuButtonItem(
          label: action.label,
          onPressed: () => _processTextAction(selection, action),
        ),
    ];
    // 工具列以父層為座標系；正文區不在螢幕頂端，狀態列 padding 不適用。
    return MediaQuery.removePadding(
      context: context,
      removeTop: true,
      removeBottom: true,
      child: AdaptiveTextSelectionToolbar.buttonItems(
        anchors: TextSelectionToolbarAnchors(
          primaryAnchor: Offset(centerX, boxes.first.top),
          secondaryAnchor: Offset(centerX, last.bottom + handleHeight),
        ),
        buttonItems: items,
      ),
    );
  }

  Future<void> _copy(ReaderTextSelection selection) async {
    final text = selection.text;
    widget.selection.clear();
    await Clipboard.setData(ClipboardData(text: text));
  }

  Future<void> _webSearch(ReaderTextSelection selection) async {
    final query = Uri.encodeQueryComponent(selection.text.trim());
    widget.selection.clear();
    await launchExternalUrlWithFeedback(context, '$_webSearchUrl$query');
  }

  void _processTextAction(
    ReaderTextSelection selection,
    ProcessTextAction action,
  ) {
    final text = selection.text;
    widget.selection.clear();
    // 正文唯讀；對方 App 回傳的文字不需要，結果要等使用者從對方 App 返回
    // 才完成，所以不等待。
    unawaited(
      _processText
          .processTextAction(action.id, text, true)
          .then<void>(
            (_) {},
            onError: (Object error, StackTrace stackTrace) => AppLog.e(
              '文字處理動作失敗: ${action.label}',
              error: error,
              stackTrace: stackTrace,
            ),
          ),
    );
  }
}

final class _SelectionPainter extends CustomPainter {
  const _SelectionPainter({required this.boxes, required this.color});

  final List<HybridLineBox> boxes;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // 跨出正文可視區的行框不畫進上下邊距與頁尾；把手另外畫，不受影響。
    canvas.clipRect(Offset.zero & size);
    final paint = Paint()..color = color;
    for (final box in boxes) {
      canvas.drawRect(
        Rect.fromLTRB(box.left, box.top, box.right, box.bottom),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SelectionPainter oldDelegate) =>
      oldDelegate.color != color || !_sameBoxes(oldDelegate.boxes, boxes);

  static bool _sameBoxes(List<HybridLineBox> a, List<HybridLineBox> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i += 1) {
      if (a[i].left != b[i].left ||
          a[i].top != b[i].top ||
          a[i].right != b[i].right ||
          a[i].bottom != b[i].bottom) {
        return false;
      }
    }
    return true;
  }
}
