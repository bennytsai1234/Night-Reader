import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';

/// 開關 [ReaderV2SidePanel] 的遙控器，由閱讀頁建立與釋放。
class ReaderV2SidePanelController {
  _ReaderV2SidePanelState? _state;

  final ValueNotifier<bool> _shown = ValueNotifier(false);

  /// 面板在畫面上：從準備打開（或手指按在左緣）到收完為止。面板內容聽它，
  /// 變成 true 時重設成剛打開的樣子；收著時不理會目前章這類變化。
  ValueListenable<bool> get shown => _shown;

  /// 打開中：從要求打開到開始收起為止（同 Scaffold 抽屜的 isDrawerOpen）。
  bool get isOpen => _state?._open ?? false;

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
class ReaderV2SidePanel extends StatefulWidget {
  const ReaderV2SidePanel({
    super.key,
    required this.controller,
    required this.panel,
    required this.child,
    this.onOpenChanged,
    this.onClosed,
  });

  final ReaderV2SidePanelController controller;

  /// 面板本身（[Drawer]）。
  final Widget panel;
  final Widget child;

  /// 開始打開（true）與開始收起（false）時呼叫。
  final ValueChanged<bool>? onOpenChanged;

  /// 收到底、面板離開畫面時呼叫。
  final VoidCallback? onClosed;

  @override
  State<ReaderV2SidePanel> createState() => _ReaderV2SidePanelState();
}

class _ReaderV2SidePanelState extends State<ReaderV2SidePanel>
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

  /// 面板建過了，之後一直掛著。
  bool _built = false;
  bool _open = false;

  /// 上次收完之後打開過：收完時才通知 [ReaderV2SidePanel.onClosed]。只是手指
  /// 按在左緣、或拉一點就放掉彈回去，不算打開過。
  bool _openedSinceClosed = false;

  /// 每次要求打開或收起加一，作廢還沒開始的滑出。
  int _trip = 0;
  Timer? _holdTimer;

  /// 收著時沿用的面板元件。
  Widget? _panel;

  ValueNotifier<bool> get _shown => widget.controller._shown;

  @override
  void initState() {
    super.initState();
    widget.controller._state = this;
  }

  @override
  void didUpdateWidget(ReaderV2SidePanel oldWidget) {
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
    _holdTimer?.cancel();
    if (widget.controller._state == this) widget.controller._state = null;
    _position.dispose();
    super.dispose();
  }

  double get _width {
    final box = _panelKey.currentContext?.findRenderObject();
    return box is RenderBox && box.hasSize ? box.size.width : 304;
  }

  /// 把面板放上畫面（還在左邊外面），換成最新的面板元件。
  void _prepare() {
    if (_built && _shown.value) return;
    setState(() {
      _built = true;
      _panel = widget.panel;
    });
    _shown.value = true;
  }

  void _setOpen(bool open) {
    if (_open == open) return;
    _open = open;
    if (open) _openedSinceClosed = true;
    if (!open) {
      _trip++;
      _holdTimer?.cancel();
    }
    widget.onOpenChanged?.call(open);
  }

  void _requestOpen() {
    if (_open) return;
    _setOpen(true);
    final trip = ++_trip;
    if (!_position.isDismissed) {
      // 收起途中又打開：從這裡滑回去。
      _position.fling();
      return;
    }
    _prepare();
    final started = Stopwatch()..start();
    unawaited(
      SchedulerBinding.instance.endOfFrame.then((_) {
        if (!mounted || trip != _trip) return;
        if (started.elapsed <= _heavyFrame) {
          _position.fling();
          return;
        }
        _holdTimer = Timer(AppMotion.stillGap, () {
          if (mounted && trip == _trip) _position.fling();
        });
      }),
    );
  }

  void _requestClose() {
    if (!_open && _position.isDismissed) return;
    _setOpen(false);
    if (_position.isDismissed) {
      _finishClosed();
    } else {
      _position.fling(velocity: -1);
    }
  }

  void _onStatus(AnimationStatus status) {
    if (status.isDismissed && !_open) _finishClosed();
  }

  void _finishClosed() {
    if (!_shown.value) return;
    _shown.value = false;
    setState(() {});
    if (!_openedSinceClosed) return;
    _openedSinceClosed = false;
    widget.onClosed?.call();
  }

  void _handleDragDown(DragDownDetails details) {
    _position.stop();
    _prepare();
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    _position.value += details.primaryDelta! / _width;
  }

  void _handleDragEnd(DragEndDetails details) {
    if (_position.isDismissed) {
      if (!_open) _finishClosed();
      return;
    }
    final velocity = details.velocity.pixelsPerSecond.dx;
    if (velocity.abs() >= _minFlingVelocity) {
      final visualVelocity = velocity / _width;
      _setOpen(visualVelocity > 0);
      _position.fling(velocity: visualVelocity);
    } else if (_position.value < 0.5) {
      _requestClose();
    } else {
      _settleOpen();
    }
  }

  /// 在目錄裡上下捲動時，左右拖曳的手勢在按下時就準備、判定是上下捲之後
  /// 退出，走到這裡：面板沒被拉動過，停在原處。
  void _handleDragCancel() {
    if (_position.isAnimating) return;
    if (_position.isDismissed) {
      if (!_open) _finishClosed();
    } else if (_position.value < 0.5) {
      _requestClose();
    } else {
      _settleOpen();
    }
  }

  /// 放手時過了一半：滑到全開。已經全開就不動，不播一段原地的動畫（那幾幀
  /// 暗幕會跟著重畫）。
  void _settleOpen() {
    _setOpen(true);
    if (!_position.isCompleted) _position.fling();
  }

  /// 面板在畫面上或打開中：暗幕與面板接手整個畫面的觸控；否則只有左緣。
  bool get _covering => _open || !_position.isDismissed;

  @override
  Widget build(BuildContext context) {
    final shown = _shown.value;
    if (shown) _panel = widget.panel;
    final scrim = DrawerTheme.of(context).scrimColor ?? Colors.black54;
    final edge = _edgeDragWidth + MediaQuery.paddingOf(context).left;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        // 同一個手勢偵測一直掛在這裡：從左緣拖出來的那一下，面板出現後
        // 照樣跟著手指。
        _EdgeHitRegion(
          edgeWidth: edge,
          covering: () => _covering,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            excludeFromSemantics: true,
            onHorizontalDragDown: _handleDragDown,
            onHorizontalDragUpdate: _handleDragUpdate,
            onHorizontalDragEnd: _handleDragEnd,
            onHorizontalDragCancel: _handleDragCancel,
            child: _built
                ? Offstage(
                    offstage: !shown,
                    child: TickerMode(
                      enabled: shown,
                      // 暗幕與面板自成一層：滑動時每一幀改暗幕濃淡、平移
                      // 面板，只重畫這一層，底下的閱讀畫面不跟著重畫。
                      child: RepaintBoundary(
                        child: _buildPanel(context, scrim),
                      ),
                    ),
                  )
                : const SizedBox.expand(),
          ),
        ),
      ],
    );
  }

  Widget _buildPanel(BuildContext context, Color scrim) {
    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedBuilder(
          animation: _position,
          builder: (context, _) => IgnorePointer(
            ignoring: !_covering,
            child: BlockSemantics(
              blocking: _open,
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
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: AnimatedBuilder(
            animation: _position,
            builder: (context, child) => FractionalTranslation(
              translation: Offset(_position.value - 1, 0),
              child: child,
            ),
            child: ExcludeFocus(
              excluding: !_open,
              child: RepaintBoundary(key: _panelKey, child: _panel),
            ),
          ),
        ),
      ],
    );
  }
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
    if (!covering() && position.dx > edgeWidth) return false;
    return super.hitTest(result, position: position);
  }
}
