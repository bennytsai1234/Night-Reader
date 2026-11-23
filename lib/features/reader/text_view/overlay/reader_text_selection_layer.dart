import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:night_reader/shared/widgets/text/ui_text.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'package:night_reader/core/diagnostics/app_log_service.dart';
import 'package:night_reader/core/models/reading/excerpt_text.dart';
import 'package:night_reader/features/about/external_url_launcher.dart';
import 'package:night_reader/features/reader/text_view/core/text_view_types.dart';
import 'package:night_reader/features/reader/text_view/overlay/selection_service.dart';

/// 正文選字的反白、兩端把手與選單。
///
/// 疊在 [child]（正文與它的點擊／長按手勢）之上、作為兄弟節點：按把手或
/// 選單不會落到正文的點擊層而被當成「取消選取」。座標一律是正文 viewport
/// 本地座標，幾何換算由閱讀畫面提供。把手拖出正文區上下緣時正文自己捲
/// （[autoScrollBy]），選取跟著延伸到這一章的章首或章末為止。
final class ReaderTextSelectionLayer extends StatefulWidget {
  const ReaderTextSelectionLayer({
    super.key,
    required this.selection,
    required this.repaint,
    required this.paintFor,
    required this.caretAt,
    this.autoScrollBy,
    this.onAutoScrollEnd,
    this.onHide,
    this.onReplace,
    this.onBookmark,
    this.onHighlight,
    required this.highlightColor,
    required this.child,
  });

  final SelectionService selection;

  /// 正文捲動時重算框位置。
  final Listenable repaint;

  /// 選取在高 viewportHeight 的 viewport 上要畫的東西：看得到的字形框與
  /// 兩端的行框。
  final SelectionPaint Function(
    ReaderTextSelection selection,
    double viewportHeight,
  )
  paintFor;

  /// viewport 上一點最近的游標位置（章內 offset）。
  final int? Function(ReaderTextSelection selection, Offset point) caretAt;

  /// 把正文捲 delta（往下讀為正）；捲不動時回傳 false。沒給就不自動捲動。
  final Future<bool> Function(double delta)? autoScrollBy;

  /// 自動捲動過的拖曳結束了：正文停在這裡，記下閱讀位置。
  final VoidCallback? onAutoScrollEnd;

  /// 選單的「隱藏」：用選到的字新增一條換成空白的替換規則（例如藏掉廣
  /// 告）；沒給就不顯示，選取跨過插圖時灰掉。
  final ValueChanged<ReaderTextSelection>? onHide;

  /// 選單的「替換」：用選到的字開一條新的替換規則，要換成的字由使用者填；
  /// 沒給就不顯示，選取跨過插圖時灰掉。
  final ValueChanged<ReaderTextSelection>? onReplace;

  /// 選單的「書籤」：在選到的字那一句留一個書籤；沒給就不顯示。
  final ValueChanged<ReaderTextSelection>? onBookmark;

  /// 「⋮」裡的「標註」：把選到的字畫上底色或底線；沒給就不顯示。
  final ValueChanged<ReaderTextSelection>? onHighlight;

  final Color highlightColor;
  final Widget child;

  @override
  State<ReaderTextSelectionLayer> createState() =>
      _ReaderTextSelectionLayerState();
}

class _ReaderTextSelectionLayerState extends State<ReaderTextSelectionLayer>
    with SingleTickerProviderStateMixin {
  static const double _selectionAlpha = 0.35;
  static const String _webSearchUrl = 'https://www.google.com/search?q=';

  // 以下照 Flutter 內建選字（`Scrollable` 的選取與 `EdgeDraggingAutoScroller`）：
  // 手指超出正文區的距離最多算到這麼多，乘上速度係數就是每秒捲多少。
  static const double _overDragMax = 20;
  static const double _autoScrollVelocityScalar = 30;

  /// 選單要放在字上方時，離正文區頂端至少要有的空間：工具列高加上和字、
  /// 和邊緣的距離（同 [_SelectionToolbarWithMoreState]）。
  static const double _toolbarRoom = 44 + 8 * 3;

  final ProcessTextService _processText = DefaultProcessTextService();
  List<ProcessTextAction> _processTextActions = const <ProcessTextAction>[];

  /// 拖動中的那一端（越過另一端時跟著換）。
  SelectionEdge? _dragEdge;

  /// 接住這次拖曳的把手；那一端捲出畫面時把手照樣留著（看不見），拖曳才
  /// 不會中斷。
  SelectionEdge? _draggedHandle;

  /// 拖動中游標的位置（行的中間）與手指的位置，viewport 座標。
  Offset? _dragPoint;
  Offset? _finger;
  double _viewportHeight = 0;

  /// 每個把手最後畫在哪一行。
  final Map<SelectionEdge, LineBox> _handleBoxes = <SelectionEdge, LineBox>{};

  late final Ticker _autoScroll = createTicker(_onAutoScrollTick);
  Duration _lastTick = Duration.zero;
  bool _scrollInFlight = false;
  bool _autoScrolled = false;

  @override
  void initState() {
    super.initState();
    widget.selection.addListener(_onSelectionChanged);
    // 與 EditableText 相同：系統可處理文字的 App（翻譯、字典…）只查一次。
    unawaited(
      _processText.queryTextActions().then((actions) {
        if (mounted) setState(() => _processTextActions = actions);
      }),
    );
  }

  @override
  void didUpdateWidget(ReaderTextSelectionLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.selection, widget.selection)) {
      oldWidget.selection.removeListener(_onSelectionChanged);
      widget.selection.addListener(_onSelectionChanged);
    }
  }

  @override
  void dispose() {
    widget.selection.removeListener(_onSelectionChanged);
    _autoScroll.dispose();
    super.dispose();
  }

  /// 選取被收掉（捲動、蓋紙、跳章、開選單…）時，拖曳與自動捲動一起作廢；
  /// 捲動位置歸收掉它的那一方，不在這裡記。收掉可能發生在建構途中，所以
  /// 不呼叫 setState；選取層照新的狀態重建。
  void _onSelectionChanged() {
    if (widget.selection.selection == null) _resetDrag(settle: false);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      // 正文會畫出這一區，由閱讀頁框架裁切（見 ReaderTextView）。
      clipBehavior: Clip.none,
      children: <Widget>[
        widget.child,
        LayoutBuilder(
          builder: (context, constraints) {
            _viewportHeight = constraints.maxHeight;
            return ListenableBuilder(
              listenable: Listenable.merge(<Listenable>[
                widget.selection,
                widget.repaint,
              ]),
              builder: (context, _) => _buildSelection(context),
            );
          },
        ),
      ],
    );
  }

  Widget _buildSelection(BuildContext context) {
    final selection = widget.selection.selection;
    if (selection == null) return const SizedBox.shrink();
    final paint = widget.paintFor(selection, _viewportHeight);
    if (paint.boxes.isEmpty && _draggedHandle == null) {
      return const SizedBox.shrink();
    }
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        IgnorePointer(
          child: CustomPaint(
            painter: _SelectionPainter(
              boxes: paint.boxes,
              color: widget.highlightColor.withValues(alpha: _selectionAlpha),
            ),
          ),
        ),
        for (final (edge, box) in [
          (SelectionEdge.start, paint.startBox),
          (SelectionEdge.end, paint.endBox),
        ])
          if (box != null)
            _buildHandle(_handleBoxes[edge] = box, edge)
          else if (_draggedHandle == edge && _handleBoxes[edge] != null)
            _buildHandle(_handleBoxes[edge]!, edge, visible: false),
        if (_dragEdge == null && paint.boxes.isNotEmpty)
          _buildToolbar(context, selection, paint),
      ],
    );
  }

  Widget _buildHandle(LineBox box, SelectionEdge edge, {bool visible = true}) {
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
        onPanStart: (details) => setState(() {
          _dragEdge = edge;
          _draggedHandle = edge;
          _dragPoint = Offset(caretX, (box.top + box.bottom) / 2);
          _finger = _localOf(details.globalPosition);
        }),
        onPanUpdate: _handleDragUpdate,
        onPanEnd: (_) => _endDrag(),
        onPanCancel: _endDrag,
        child: Opacity(
          opacity: visible ? 1 : 0,
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
      ),
    );
  }

  Offset? _localOf(Offset global) {
    final box = context.findRenderObject();
    return box is RenderBox && box.hasSize ? box.globalToLocal(global) : null;
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    final point = _dragPoint;
    if (point == null) return;
    _dragPoint = point + details.delta;
    _finger = _localOf(details.globalPosition);
    _applyDrag();
    if (widget.autoScrollBy != null &&
        _overDrag() != 0 &&
        !_autoScroll.isActive) {
      _lastTick = Duration.zero;
      unawaited(_autoScroll.start());
    }
  }

  /// 照目前拖到的位置移動選取的一端。正文自動捲動時手指不動、底下的字在
  /// 動，所以每捲一下也重算；游標夾在正文區裡，拖出上下緣時選到邊緣那一行。
  void _applyDrag() {
    final selection = widget.selection.selection;
    final edge = _dragEdge;
    final point = _dragPoint;
    if (selection == null || edge == null || point == null) return;
    final inside = Offset(
      point.dx,
      point.dy.clamp(0, math.max(0, _viewportHeight - 1)).toDouble(),
    );
    final offset = widget.caretAt(selection, inside);
    if (offset == null) return;
    final moved = selection.moveEdge(edge, offset);
    _dragEdge = moved.edge;
    if (moved.selection.range == selection.range) return;
    widget.selection.select(moved.selection);
    unawaited(HapticFeedback.selectionClick());
  }

  /// 手指超出正文區上緣（負）或下緣（正）多少，最多算到 [_overDragMax]。
  double _overDrag() {
    final finger = _finger;
    if (finger == null) return 0;
    if (finger.dy < 0) return -math.min(-finger.dy, _overDragMax);
    if (finger.dy > _viewportHeight) {
      return math.min(finger.dy - _viewportHeight, _overDragMax);
    }
    return 0;
  }

  void _onAutoScrollTick(Duration elapsed) {
    final dt = elapsed - _lastTick;
    _lastTick = elapsed;
    final selection = widget.selection.selection;
    final scrollBy = widget.autoScrollBy;
    final overDrag = _overDrag();
    if (selection == null || scrollBy == null || overDrag == 0) {
      _autoScroll.stop();
      return;
    }
    // 拖著的那一端已經到這一章的章首或章末：那裡就在畫面上，不再捲。
    final bounds = selection.bounds;
    if ((overDrag < 0 &&
            _dragEdge == SelectionEdge.start &&
            selection.range.start <= bounds.start) ||
        (overDrag > 0 &&
            _dragEdge == SelectionEdge.end &&
            selection.range.end >= bounds.end)) {
      return;
    }
    if (_scrollInFlight) return;
    final delta =
        overDrag *
        _autoScrollVelocityScalar *
        dt.inMicroseconds /
        Duration.microsecondsPerSecond;
    if (delta == 0) return;
    _scrollInFlight = true;
    unawaited(
      scrollBy(delta).then((moved) {
        _scrollInFlight = false;
        if (!mounted || _dragEdge == null) return;
        if (moved) _autoScrolled = true;
        _applyDrag();
      }),
    );
  }

  void _resetDrag({required bool settle}) {
    _autoScroll.stop();
    _dragEdge = null;
    _draggedHandle = null;
    _dragPoint = null;
    _finger = null;
    final scrolled = _autoScrolled;
    _autoScrolled = false;
    if (settle && scrolled) widget.onAutoScrollEnd?.call();
  }

  void _endDrag() {
    if (!mounted) return;
    setState(() => _resetDrag(settle: true));
  }

  Widget _buildToolbar(
    BuildContext context,
    ReaderTextSelection selection,
    SelectionPaint paint,
  ) {
    final boxes = paint.boxes;
    final left = boxes.map((box) => box.left).reduce(math.min);
    final right = boxes.map((box) => box.right).reduce(math.max);
    final centerX = (left + right) / 2;
    final last = boxes.last;
    final handleHeight = materialTextSelectionHandleControls
        .getHandleSize(last.bottom - last.top)
        .height;
    // 選取跨出畫面時，選單放在看得到的那一段上：開頭在畫面上方外面時放到
    // 正文區頂端（蓋在選到的字上），也不放到正文區底下看不到的地方。
    final top = paint.startBox == null
        ? math.max(boxes.first.top, _toolbarRoom)
        : boxes.first.top;
    final bottom = math.min(
      last.bottom + (paint.endBox == null ? 0 : handleHeight),
      math.max(0.0, _viewportHeight - _toolbarRoom),
    );
    // 跨過插圖時寫不成一條規則（插圖會被一起藏掉），「隱藏」「替換」灰掉。
    final rulesAllowed = !selection.crossesIllustration;
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
          onPressed: rulesAllowed
              ? () {
                  widget.selection.clear();
                  onHide(selection);
                }
              : null,
        ),
      if (widget.onReplace case final onReplace?)
        ContextMenuButtonItem(
          label: '替換',
          onPressed: rulesAllowed
              ? () {
                  widget.selection.clear();
                  onReplace(selection);
                }
              : null,
        ),
      if (widget.onBookmark case final onBookmark?)
        ContextMenuButtonItem(
          label: '書籤',
          onPressed: () {
            widget.selection.clear();
            onBookmark(selection);
          },
        ),
    ];
    // 「⋮」裡：自己的「標註」在前，系統能處理文字的 App 在後。
    final moreItems = <ContextMenuButtonItem>[
      if (widget.onHighlight case final onHighlight?)
        ContextMenuButtonItem(
          label: '標註',
          onPressed: () {
            widget.selection.clear();
            onHighlight(selection);
          },
        ),
      for (final action in _processTextActions)
        ContextMenuButtonItem(
          label: action.label,
          onPressed: () => _processTextAction(selection, action),
        ),
    ];
    final anchors = TextSelectionToolbarAnchors(
      primaryAnchor: Offset(centerX, top),
      secondaryAnchor: Offset(centerX, bottom),
    );
    // 工具列以父層為座標系；正文區不在螢幕頂端，狀態列 padding 不適用。
    return MediaQuery.removePadding(
      context: context,
      removeTop: true,
      removeBottom: true,
      child: moreItems.isEmpty
          ? AdaptiveTextSelectionToolbar.buttonItems(
              anchors: anchors,
              buttonItems: items,
            )
          : _SelectionToolbarWithMore(
              // 選了別的字就從收起的樣子開始。
              key: ValueKey(selection.range),
              anchors: anchors,
              items: items,
              moreItems: moreItems,
            ),
    );
  }

  void _processTextAction(
    ReaderTextSelection selection,
    ProcessTextAction action,
  ) {
    final text = withSingleLineBreaks(selection.text);
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

  /// 複製與分享給其他 App 時段落之間只換一行；搜尋時換成空格。
  Future<void> _copy(ReaderTextSelection selection) async {
    final text = withSingleLineBreaks(selection.text);
    widget.selection.clear();
    await Clipboard.setData(ClipboardData(text: text));
  }

  Future<void> _webSearch(ReaderTextSelection selection) async {
    final query = Uri.encodeQueryComponent(
      selection.text.trim().replaceAll(RegExp(r'\n+'), ' '),
    );
    widget.selection.clear();
    await launchExternalUrlWithFeedback(context, '$_webSearchUrl$query');
  }
}

/// 有「⋮」的選單：列上固定只有 [items]，[moreItems]（「標註」與系統能處理
/// 文字的 App）一律收在「⋮」裡，按下展開成直式選單、左上（選單在字上方
/// 時是左下）的返回鍵收回。對方 App 的名稱由它自己決定，會混進簡體字，
/// 所以不和自己的按鈕並排；「標註」不常用，收起來讓列上放得下。
///
/// Flutter 的 [TextSelectionToolbar] 只在寬度放不下時才把按鈕收進「⋮」，
/// 指定不了哪些收起來；這裡照它的樣子（外框、按鈕、位置、展開的時間與
/// 展開後靠尾端對齊）自己排。一排放不下時整排縮小，App 多到放不下時清單
/// 捲動，按鈕都按得到。
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

  final GlobalKey _toolbarKey = GlobalKey();
  bool _open = false;

  /// 收起時工具列的寬度：展開後的選單比它窄時靠尾端對齊，「⋮」那一側
  /// 不動（Flutter 的 `_TextSelectionToolbarTrailingEdgeAlign`）。
  double? _closedWidth;

  void _toggle() {
    setState(() {
      _closedWidth = _open ? null : _toolbarKey.currentContext?.size?.width;
      _open = !_open;
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => _build(context, constraints.maxHeight),
  );

  Widget _build(BuildContext context, double maxHeight) {
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
      onPressed: _toggle,
    );
    // 工具列能用的高度：在字上方時位置最高到頂（選單比上方的空間高就蓋過
    // 選到的字），在字下方時從選取下緣到底。
    final area = maxHeight - paddingAbove - _screenPadding;
    final menuMaxHeight = math.max(
      _toolbarHeight,
      fitsAbove ? area : area - (below.dy - local.dy),
    );
    final Widget content;
    if (_open) {
      final menu = [
        for (final item in widget.moreItems)
          TextSelectionToolbarTextButton(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: AlignmentDirectional.centerStart,
            onPressed: item.onPressed,
            child: UiText(
              AdaptiveTextSelectionToolbar.getButtonLabel(context, item),
            ),
          ),
      ];
      final back = Align(
        alignment: AlignmentDirectional.centerStart,
        child: toggle,
      );
      // App 多到放不下時清單捲動，返回鍵固定在「⋮」原本那一排；和
      // Flutter 一樣，選單在字上方時往上展開。
      final list = Flexible(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: menu,
          ),
        ),
      );
      content = ConstrainedBox(
        constraints: BoxConstraints(maxHeight: menuMaxHeight),
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: fitsAbove ? [list, back] : [back, list],
          ),
        ),
      );
    } else {
      final count = widget.items.length + 1;
      // 窄視窗或系統字級放大到一排放不下時整排等比縮小，每個按鈕都還按得到。
      content = SizedBox(
        height: _toolbarHeight,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < widget.items.length; i++)
                TextSelectionToolbarTextButton(
                  padding: TextSelectionToolbarTextButton.getPadding(i, count),
                  onPressed: widget.items[i].onPressed,
                  child: UiText(
                    AdaptiveTextSelectionToolbar.getButtonLabel(
                      context,
                      widget.items[i],
                    ),
                  ),
                ),
              toggle,
            ],
          ),
        ),
      );
    }
    final toolbar = Material(
      key: _toolbarKey,
      borderRadius: const BorderRadius.all(Radius.circular(_toolbarHeight / 2)),
      clipBehavior: Clip.antiAlias,
      color: Theme.of(context).colorScheme.surface,
      elevation: 1,
      type: MaterialType.card,
      child: content,
    );

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
          child: switch (_closedWidth) {
            final width? => ConstrainedBox(
              constraints: BoxConstraints(minWidth: width),
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                widthFactor: 1,
                heightFactor: 1,
                child: toolbar,
              ),
            ),
            null => toolbar,
          },
        ),
      ),
    );
  }
}

final class _SelectionPainter extends CustomPainter {
  const _SelectionPainter({required this.boxes, required this.color});

  final List<LineBox> boxes;
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

  static bool _sameBoxes(List<LineBox> a, List<LineBox> b) {
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
