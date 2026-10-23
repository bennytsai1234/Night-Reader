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
    this.onHide,
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

  /// 選單的「隱藏」：用選到的字新增一條換成空白的替換規則（例如藏掉廣
  /// 告）；沒給就不顯示。
  final ValueChanged<ReaderTextSelection>? onHide;

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
      // 正文會畫出這一區，由閱讀頁框架裁切（見 HybridReaderScreen）。
      clipBehavior: Clip.none,
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
      if (widget.onHide case final onHide?)
        ContextMenuButtonItem(
          label: '隱藏',
          onPressed: () {
            widget.selection.clear();
            onHide(selection);
          },
        ),
    ];
    final anchors = TextSelectionToolbarAnchors(
      primaryAnchor: Offset(centerX, boxes.first.top),
      secondaryAnchor: Offset(centerX, last.bottom + handleHeight),
    );
    // 工具列以父層為座標系；正文區不在螢幕頂端，狀態列 padding 不適用。
    return MediaQuery.removePadding(
      context: context,
      removeTop: true,
      removeBottom: true,
      child: _processTextActions.isEmpty
          ? AdaptiveTextSelectionToolbar.buttonItems(
              anchors: anchors,
              buttonItems: items,
            )
          : _SelectionToolbarWithMore(
              // 選了別的字就從收起的樣子開始。
              key: ValueKey(selection.range),
              anchors: anchors,
              items: items,
              moreItems: [
                for (final action in _processTextActions)
                  ContextMenuButtonItem(
                    label: action.label,
                    onPressed: () => _processTextAction(selection, action),
                  ),
              ],
            ),
    );
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
}

/// 有系統文字處理 App 時的選單：列上固定只有 [items]，[moreItems] 一律收
/// 在「⋮」裡，按下展開成直式選單、左上（選單在字上方時是左下）的返回鍵
/// 收回。對方 App 的名稱由它自己決定，會混進簡體字，所以不和自己的按鈕
/// 並排。
///
/// Flutter 的 [TextSelectionToolbar] 只在寬度放不下時才把按鈕收進「⋮」，
/// 指定不了哪些收起來；這裡照它的樣子（外框、按鈕、位置與展開的時間）
/// 自己排。
class _SelectionToolbarWithMore extends StatefulWidget {
  const _SelectionToolbarWithMore({
    super.key,
    required this.anchors,
    required this.items,
    required this.moreItems,
  });

  final TextSelectionToolbarAnchors anchors;
  final List<ContextMenuButtonItem> items;
  final List<ContextMenuButtonItem> moreItems;

  @override
  State<_SelectionToolbarWithMore> createState() =>
      _SelectionToolbarWithMoreState();
}

class _SelectionToolbarWithMoreState extends State<_SelectionToolbarWithMore> {
  // 以下照 Flutter 的 TextSelectionToolbar：工具列高、和選取的距離、離螢幕
  // 邊的距離與展開的時間。
  static const double _toolbarHeight = 44;
  static const double _contentDistance = 8;
  static const double _screenPadding = 8;
  static const Duration _expand = Duration(milliseconds: 140);

  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final above =
        widget.anchors.primaryAnchor - const Offset(0, _contentDistance);
    final below =
        (widget.anchors.secondaryAnchor ?? widget.anchors.primaryAnchor) +
        const Offset(0, TextSelectionToolbar.kToolbarContentDistanceBelow);
    final paddingAbove = MediaQuery.paddingOf(context).top + _screenPadding;
    final fitsAbove =
        _toolbarHeight <= above.dy - _contentDistance - paddingAbove;
    final local = Offset(_screenPadding, paddingAbove);

    final toggle = IconButton(
      icon: Icon(_open ? Icons.arrow_back : Icons.more_vert),
      tooltip: _open
          ? localizations.backButtonTooltip
          : localizations.moreButtonTooltip,
      onPressed: () => setState(() => _open = !_open),
    );
    final Widget content;
    if (_open) {
      final menu = [
        for (final item in widget.moreItems)
          TextSelectionToolbarTextButton(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: AlignmentDirectional.centerStart,
            onPressed: item.onPressed,
            child: Text(
              AdaptiveTextSelectionToolbar.getButtonLabel(context, item),
            ),
          ),
      ];
      final back = Align(
        alignment: AlignmentDirectional.centerStart,
        child: toggle,
      );
      // 和 Flutter 一樣：選單在字上方時往上展開，返回鍵留在「⋮」原本那一排。
      content = IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: fitsAbove ? [...menu, back] : [back, ...menu],
        ),
      );
    } else {
      final count = widget.items.length + 1;
      content = SizedBox(
        height: _toolbarHeight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < widget.items.length; i++)
              TextSelectionToolbarTextButton(
                padding: TextSelectionToolbarTextButton.getPadding(i, count),
                onPressed: widget.items[i].onPressed,
                child: Text(
                  AdaptiveTextSelectionToolbar.getButtonLabel(
                    context,
                    widget.items[i],
                  ),
                ),
              ),
            toggle,
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(
        _screenPadding,
        paddingAbove,
        _screenPadding,
        _screenPadding,
      ),
      child: CustomSingleChildLayout(
        delegate: TextSelectionToolbarLayoutDelegate(
          anchorAbove: above - local,
          anchorBelow: below - local,
          fitsAbove: fitsAbove,
        ),
        child: AnimatedSize(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : _expand,
          child: Material(
            borderRadius: const BorderRadius.all(
              Radius.circular(_toolbarHeight / 2),
            ),
            clipBehavior: Clip.antiAlias,
            color: Theme.of(context).colorScheme.surface,
            elevation: 1,
            type: MaterialType.card,
            child: content,
          ),
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
