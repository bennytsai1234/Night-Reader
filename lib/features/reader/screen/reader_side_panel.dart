import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:night_reader/features/reader/features/menu/reader_menu_style.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/pixel_translation.dart';

/// 開關 [ReaderSidePanel] 的遙控器，由閱讀頁建立與釋放。
class ReaderSidePanelController {
  _ReaderSidePanelState? _state;

  final ValueNotifier<bool> _shown = ValueNotifier(false);

  /// 面板在畫面上：從準備打開（或手指按在左緣）到收完為止。面板內容聽它，
  /// 變成 true 時重設成剛打開的樣子；收著時不理會目前章這類變化。
  ValueListenable<bool> get shown => _shown;

  /// 打開中：從要求打開到開始收起為止（同 Scaffold 抽屜的 isDrawerOpen）。
  bool get isOpen => _state?._phase.open ?? false;

  /// 面板佔著畫面：打開中，或手指正拉著、正在收起而還在畫面上。返回鍵
  /// 這時只收面板。
  bool get isOnScreen => _state?._phase.covering ?? false;

  void open() => _state?._requestOpen();

  void close() => _state?._requestClose();

  void dispose() => _shown.dispose();
}

/// 閱讀器左側的面板（目錄），蓋在 [child] 上：暗幕、拖曳、點旁邊收起與
/// 速度都照 Flutter 的 Scaffold 抽屜。
///
/// 和 Scaffold 抽屜不同的是面板一直掛著：第一次要用時才建，之後收著時留在
/// 元件樹裡、不畫，也不跟著閱讀頁重建（沿用上一次的 [panel]，主題換了照樣
/// 跟著變）。打開時先在畫面靜止的那一幀把面板更新好，那一幀很重時再停
/// [AppMotion.stillGap]，滑出的每一幀只平移面板、改暗幕的濃淡（ADR 0037
/// 策略一、二）。手指按在左緣時就先準備，往右拖時面板已經建好，只跟著手指
/// 走（策略四）。
class ReaderSidePanel extends StatefulWidget {
  const ReaderSidePanel({
    super.key,
    required this.controller,
    required this.panel,
    required this.child,
    this.onOpenChanged,
    this.onClosed,
  });

  final ReaderSidePanelController controller;

  /// 面板本身（[Drawer]）。
  final Widget panel;
  final Widget child;

  /// 開始打開（true）與開始收起（false）時呼叫。
  final ValueChanged<bool>? onOpenChanged;

  /// 收到底、面板離開畫面時呼叫。
  final VoidCallback? onClosed;

  @override
  State<ReaderSidePanel> createState() => _ReaderSidePanelState();
}

class _ReaderSidePanelState extends State<ReaderSidePanel>
    with SingleTickerProviderStateMixin {
  /// 照 Flutter 的抽屜：收放的基準時間、甩動算數的最低速度與左緣的感應寬度。
  static const Duration _settleDuration = Duration(milliseconds: 246);
  static const double _minFlingVelocity = 365;
  static const double _edgeDragWidth = 20;

  /// 從要求打開到那一幀畫完超過這麼久，就是準備面板的工作很重（同按鈕
  /// 回彈的 `PressScale`）。
  static const Duration _heavyFrame = Duration(milliseconds: 16);

  late final AnimationController _position = AnimationController(
    vsync: this,
    duration: _settleDuration,
  )..addStatusListener(_onStatus);

  final GlobalKey _panelKey = GlobalKey();

  /// 面板自己的焦點範圍：打開時焦點移進來，不留在被蓋住的閱讀頁（同系統
  /// 抽屜）。
  final FocusScopeNode _focusScope = FocusScopeNode(
    debugLabel: 'ReaderSidePanel',
  );

  _Phase _phase = const _Hidden();

  /// 面板收著過幾次，和按下時記的 [_touchClosings] 對照：按著的途中面板
  /// 收著過（例如按了返回），這次觸控之後就不再動面板，面板又被打開了也
  /// 一樣。和階段同時成立，所以另記。
  int _closings = 0;
  int _touchClosings = 0;

  /// 收著時沿用的面板元件；第一次準備時才有，之後一直掛著。
  Widget? _panel;

  ValueNotifier<bool> get _shown => widget.controller._shown;

  @override
  void initState() {
    super.initState();
    widget.controller._state = this;
  }

  @override
  void didUpdateWidget(ReaderSidePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      if (oldWidget.controller._state == this) {
        oldWidget.controller._state = null;
      }
      widget.controller._state = this;
    }
  }

  @override
  void dispose() {
    if (_phase case _Preparing(:final hold)) hold?.cancel();
    if (widget.controller._state == this) widget.controller._state = null;
    _position.dispose();
    _focusScope.dispose();
    super.dispose();
  }

  double get _width {
    final box = _panelKey.currentContext?.findRenderObject();
    return box is RenderBox && box.hasSize ? box.size.width : 304;
  }

  /// 換到下一個階段：對外的通知與要不要重建都只在這裡，照前後兩個階段算。
  /// 先換好階段再動 [_position]，動畫的狀態通知是同步的。傳回 [next] 還是
  /// 不是現在的階段：開關的通知裡又要求打開或收起，就已經換成別的（剩下的
  /// 通知由那一次發），呼叫的地方不再動畫。
  bool _go(_Phase next) {
    final before = _phase;
    if (identical(before, next)) return true;
    if (before case _Preparing(:final hold)) hold?.cancel();
    _phase = next;
    if (next is _Hidden) _closings++;
    // 建畫面只讀這三件，沒變就不重建：滑出、開始拖、放手都落在畫面正在
    // 動的幀（ADR 0037 策略二）。面板沿用同一個元件，不跟著重建。
    if (before.shown != next.shown ||
        before.covering != next.covering ||
        before.open != next.open) {
      setState(() {});
    }
    if (before.open != next.open) {
      if (next.open) FocusScope.of(context).setFirstFocus(_focusScope);
      widget.onOpenChanged?.call(next.open);
      if (!identical(_phase, next)) return false;
    }
    _shown.value = next.shown;
    if (next is _Hidden && before.opened) widget.onClosed?.call();
    return identical(_phase, next);
  }

  void _requestOpen() {
    switch (_phase) {
      case _Hidden() || _AtEdge():
        _prepareOpening();
      case _Closing() || _Dragging():
        // 收起途中、或手指拉著時要求打開：從這裡滑過去，這次拖曳剩下的不理。
        if (_go(const _Open())) _position.fling();
      case _Preparing() || _Open():
        return;
    }
  }

  /// 把面板放上畫面（還在左邊外面）、換成最新的面板元件，等這一幀畫完才
  /// 滑；那一幀很重時再停 [AppMotion.stillGap]（ADR 0037 策略一）。
  void _prepareOpening() {
    final preparing = _Preparing();
    if (!_go(preparing)) return;
    final started = Stopwatch()..start();
    unawaited(
      SchedulerBinding.instance.endOfFrame.then((_) {
        if (!mounted || _phase != preparing) return;
        if (started.elapsed <= _heavyFrame) {
          _slideOpen();
          return;
        }
        preparing.hold = Timer(AppMotion.stillGap, () {
          if (mounted && _phase == preparing) _slideOpen();
        });
      }),
    );
  }

  void _slideOpen() {
    if (_go(const _Open())) _position.fling();
  }

  void _requestClose() {
    switch (_phase) {
      case _Hidden() || _AtEdge():
        return;
      case _Preparing():
        // 還沒開始滑：面板沒出現過，直接收著。
        _go(const _Hidden());
      case _Open() || _Closing() || _Dragging():
        // 手指拉著時被要求收起（例如按返回）：這次拖曳剩下的不理。
        _slideClosed();
    }
  }

  /// 滑回左邊外面；已經在左緣就直接收著。
  void _slideClosed() {
    if (_position.isDismissed) {
      _go(const _Hidden());
      return;
    }
    if (_go(_Closing(opened: _phase.opened))) _position.fling(velocity: -1);
  }

  /// 放手時過了一半：滑到全開。已經全開就不動，不播一段原地的動畫（那幾幀
  /// 暗幕會跟著重畫）。
  void _settleOpen() {
    if (_go(const _Open()) && !_position.isCompleted) _position.fling();
  }

  /// 收到底：只在收起時算數，手指拉回左緣時還是拉著。
  void _onStatus(AnimationStatus status) {
    if (status.isDismissed && _phase is _Closing) _go(const _Hidden());
  }

  /// 手指按下：動畫停在原處，等手勢判定是不是左右拖。收著時先把面板準備
  /// 好，往右拖時面板已經建好，只跟著手指走（策略四）。
  void _handleDragDown(DragDownDetails details) {
    _touchClosings = _closings;
    _position.stop();
    if (_phase is _Hidden) _go(const _AtEdge());
  }

  /// 這次觸控按下之後面板收著過：剩下的都不理。
  bool get _touchOutlived => _touchClosings != _closings;

  /// 手指真的開始左右拖：面板交給手指，還沒開始的滑出作廢，按著時才開始
  /// 的滑出停在這裡。
  void _handleDragStart(DragStartDetails details) {
    if (_touchOutlived) return;
    final from = _phase;
    if (_go(_Dragging(open: from.open, opened: from.opened))) _position.stop();
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (_phase is! _Dragging) return;
    _position.value += details.primaryDelta! / _width;
  }

  void _handleDragEnd(DragEndDetails details) {
    final dragging = _phase;
    if (dragging is! _Dragging) return;
    // 放手時面板已經在左邊外面：拉一點就推回去，或打開後一路拖到底，都算
    // 收完。
    if (_position.isDismissed) {
      _go(const _Hidden());
      return;
    }
    final velocity = details.velocity.pixelsPerSecond.dx;
    if (velocity.abs() >= _minFlingVelocity) {
      final visualVelocity = velocity / _width;
      final next = visualVelocity > 0
          ? const _Open()
          : _Closing(opened: dragging.opened);
      if (_go(next)) _position.fling(velocity: visualVelocity);
    } else if (_position.value < 0.5) {
      _slideClosed();
    } else {
      _settleOpen();
    }
  }

  /// 按下之後沒有左右拖（點一下，或在目錄裡上下捲）：照面板停在哪一半定。
  void _handleDragCancel() {
    if (_touchOutlived || _position.isAnimating) return;
    switch (_phase) {
      case _AtEdge():
        _go(const _Hidden());
      case _Open() || _Closing():
        if (_position.value < 0.5) {
          _slideClosed();
        } else {
          _settleOpen();
        }
      case _Hidden() || _Preparing() || _Dragging():
        // 準備打開時按下又放開、沒有拖：照原本的打開繼續（點旁邊的那一下
        // 由暗幕收起）。
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final phase = _phase;
    if (phase.shown) _panel = widget.panel;
    final panel = _panel;
    final scrim = ReaderMenuStyle.of(context).scrim;
    final edge = _edgeDragWidth + MediaQuery.paddingOf(context).left;
    return Stack(
      fit: StackFit.expand,
      children: [
        // 面板佔著畫面的整段（含手指拉著、收起途中），讀屏不讀被蓋住的閱讀
        // 頁。只改這一層的排除，閱讀頁不重建。
        ExcludeSemantics(excluding: phase.covering, child: widget.child),
        // 同一個手勢偵測一直掛在這裡：從左緣拖出來的那一下，面板出現後
        // 照樣跟著手指。
        _EdgeHitRegion(
          edgeWidth: edge,
          covering: () => _phase.covering,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            excludeFromSemantics: true,
            onHorizontalDragDown: _handleDragDown,
            onHorizontalDragStart: _handleDragStart,
            onHorizontalDragUpdate: _handleDragUpdate,
            onHorizontalDragEnd: _handleDragEnd,
            onHorizontalDragCancel: _handleDragCancel,
            child: panel != null
                ? Offstage(
                    offstage: !phase.shown,
                    child: TickerMode(
                      enabled: phase.shown,
                      // 暗幕與面板自成一層：滑動時每一幀改暗幕濃淡、平移
                      // 面板，只重畫這一層，底下的閱讀畫面不跟著重畫。
                      child: RepaintBoundary(
                        child: _buildPanel(context, scrim, panel),
                      ),
                    ),
                  )
                : const SizedBox.expand(),
          ),
        ),
      ],
    );
  }

  Widget _buildPanel(BuildContext context, Color scrim, Widget panel) {
    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedBuilder(
          animation: _position,
          builder: (context, _) => IgnorePointer(
            ignoring: !_phase.covering,
            child: GestureDetector(
              onTap: _requestClose,
              child: Semantics(
                label: MaterialLocalizations.of(context)
                    .modalBarrierDismissLabel,
                child: ColoredBox(
                  color: Color.lerp(
                    scrim.withValues(alpha: 0),
                    scrim,
                    _position.value,
                  )!,
                ),
              ),
            ),
          ),
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: AnimatedBuilder(
            animation: _position,
            // 平移對齊整數實體像素：滑入時目錄的字不必每到新位置就補建
            // 字的貼圖。
            builder: (context, child) => PixelTranslation(
              fraction: Offset(_position.value - 1, 0),
              child: child,
            ),
            child: FocusScope(
              node: _focusScope,
              child: ExcludeFocus(
                excluding: !_phase.open,
                child: RepaintBoundary(key: _panelKey, child: panel),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 面板現在在哪一段（`docs/state-machines.md`「閱讀器目錄面板」）。面板的
/// 位置是 [_ReaderSidePanelState._position] 的值，不是階段。
sealed class _Phase {
  const _Phase();

  /// 面板在畫面上（可能還在左邊外面）：遙控器的 `shown`。
  bool get shown => true;

  /// 面板佔著畫面：暗幕與面板接走整個畫面的觸控、讀屏不讀閱讀頁、返回鍵
  /// 只收面板。
  bool get covering => true;

  /// 打開中：要求打開到開始收起（`isOpen`、`onOpenChanged`）。
  bool get open => false;

  /// 這一趟打開過：進入收著時才通知 `onClosed`。只是手指按在左緣、或拉
  /// 一點就放掉彈回去，不算打開過。
  bool get opened => open;
}

/// 收著：不在畫面上，只有左緣接得到觸控。
final class _Hidden extends _Phase {
  const _Hidden();

  @override
  bool get shown => false;

  @override
  bool get covering => false;
}

/// 手指按在左緣、還沒往右拖：面板在左邊外面準備好，不佔畫面。
final class _AtEdge extends _Phase {
  const _AtEdge();

  @override
  bool get covering => false;
}

/// 準備打開：面板在左邊外面換上最新的，等這一幀畫完（很重時再停一下）才
/// 滑出。每次要求打開是新的一個，等待回來時看現在還是不是它。
final class _Preparing extends _Phase {
  _Preparing();

  /// 準備那一幀很重時，停頓後才滑出的計時器。
  Timer? hold;

  @override
  bool get open => true;
}

/// 打開：滑向全開或已經全開。
final class _Open extends _Phase {
  const _Open();

  @override
  bool get open => true;
}

/// 收起：滑回左邊外面，到左緣就收著。
final class _Closing extends _Phase {
  const _Closing({required this.opened});

  @override
  final bool opened;
}

/// 拉著：面板跟著手指。打開中照拉之前。
final class _Dragging extends _Phase {
  const _Dragging({required this.open, required this.opened});

  @override
  final bool open;

  @override
  final bool opened;
}

/// 面板收著時只有左緣接得到觸控（往右拖拉出面板），其他地方直接穿過去給
/// 正文；面板在畫面上時整個畫面都歸面板。
class _EdgeHitRegion extends SingleChildRenderObjectWidget {
  const _EdgeHitRegion({
    required this.edgeWidth,
    required this.covering,
    required super.child,
  });

  final double edgeWidth;
  final bool Function() covering;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderEdgeHitRegion(edgeWidth: edgeWidth, covering: covering);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderEdgeHitRegion renderObject,
  ) {
    renderObject
      ..edgeWidth = edgeWidth
      ..covering = covering;
  }
}

class _RenderEdgeHitRegion extends RenderProxyBox {
  _RenderEdgeHitRegion({required this.edgeWidth, required this.covering});

  double edgeWidth;
  bool Function() covering;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!covering()) {
      if (position.dx > edgeWidth) return false;
      return super.hitTest(result, position: position);
    }
    // 佔著畫面時觸控一律不穿到底下：從左緣開始拖的那一幀，暗幕還沒重建、
    // 不接觸控，這時按下的另一根手指也歸面板。
    super.hitTest(result, position: position);
    return true;
  }
}
