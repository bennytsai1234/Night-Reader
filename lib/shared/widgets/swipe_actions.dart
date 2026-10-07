import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../theme/app_text_styles.dart';
import '../theme/app_tokens.dart';

/// 列滑動後露出的單一動作按鈕。
@immutable
class SwipeAction {
  const SwipeAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
    this.destructive = false,
  });

  final String label;
  final IconData icon;

  /// 按鈕底色；傳 [AppTint] 的顏色或 `context.danger`。
  final Color color;
  final VoidCallback onPressed;

  /// 刪除類動作：完整滑動時整列先滑出畫面再執行（Telegram 刪除的樣子）；
  /// 列仍存在（例如確認框取消）時再彈回原位。
  final bool destructive;
}

/// 動作按鈕寬度（Telegram 聊天列表的動作格寬度）。
const double _kActionWidth = 74.0;

/// 放開時判定為「甩動」的水平速度（px/s）；低於此值依位置決定開合。
const double _kFlingVelocity = 300.0;

/// 完整滑動觸發最外側動作的距離比例。
const double _kFullSwipeFraction = 0.6;

/// Telegram 式列滑動動作。
///
/// 水平拖動露出列尾（[trailing]，向左滑）或列首（[leading]，向右滑）的
/// 動作按鈕；拖過一半露出寬度放開會停在展開狀態，滑過列寬約 60% 會觸發
/// 最外側動作（列尾為最後一個、列首為第一個）。展開時點列本身只會收合。
/// 只使用水平拖動手勢，不攔截清單的垂直捲動；清單捲動時自動收合。
///
/// 放在 [SwipeActionsGroup] 底下時，同一組同時只會有一列展開。
class SwipeActions extends StatefulWidget {
  const SwipeActions({
    super.key,
    required this.child,
    this.leading = const [],
    this.trailing = const [],
    this.enabled = true,
  });

  final Widget child;

  /// 向右滑露出的動作，由左到右排列；第一個為完整滑動的動作。
  final List<SwipeAction> leading;

  /// 向左滑露出的動作，由左到右排列；最後一個為完整滑動的動作。
  final List<SwipeAction> trailing;
  final bool enabled;

  @override
  State<SwipeActions> createState() => _SwipeActionsState();
}

/// 讓清單內同時只有一列展開；包在清單外層即可，不需要其他設定。
class SwipeActionsGroup extends StatefulWidget {
  const SwipeActionsGroup({super.key, required this.child});

  final Widget child;

  @override
  State<SwipeActionsGroup> createState() => _SwipeActionsGroupState();
}

class _SwipeActionsGroupState extends State<SwipeActionsGroup> {
  final _SwipeGroupController _controller = _SwipeGroupController();

  @override
  Widget build(BuildContext context) {
    return _SwipeGroupScope(controller: _controller, child: widget.child);
  }
}

class _SwipeGroupController {
  _SwipeActionsState? _active;

  void activate(_SwipeActionsState row) {
    if (identical(_active, row)) return;
    _active?._close();
    _active = row;
  }

  void release(_SwipeActionsState row) {
    if (identical(_active, row)) _active = null;
  }
}

class _SwipeGroupScope extends InheritedWidget {
  const _SwipeGroupScope({required this.controller, required super.child});

  final _SwipeGroupController controller;

  @override
  bool updateShouldNotify(_SwipeGroupScope oldWidget) =>
      !identical(controller, oldWidget.controller);
}

class _SwipeActionsState extends State<SwipeActions>
    with TickerProviderStateMixin {
  /// 子元件的水平位移（px）；負值為露出列尾動作，正值為露出列首動作。
  late final AnimationController _offset = AnimationController.unbounded(
    vsync: this,
  );

  /// 完整滑動預備狀態：最外側動作撐滿露出區域。
  late final AnimationController _expand = AnimationController(
    vsync: this,
    duration: AppMotion.menu,
  );

  double _width = 0;
  bool _dragging = false;
  bool _armed = false;
  _SwipeGroupController? _group;
  ValueListenable<bool>? _scrolling;

  bool get _active =>
      widget.enabled &&
      (widget.leading.isNotEmpty || widget.trailing.isNotEmpty);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final group =
        context.dependOnInheritedWidgetOfExactType<_SwipeGroupScope>()
            ?.controller;
    if (!identical(group, _group)) {
      _group?.release(this);
      _group = group;
    }
    final scrolling = Scrollable.maybeOf(context)?.position.isScrollingNotifier;
    if (!identical(scrolling, _scrolling)) {
      _scrolling?.removeListener(_onScrollingChanged);
      _scrolling = scrolling;
      _scrolling?.addListener(_onScrollingChanged);
    }
  }

  @override
  void didUpdateWidget(SwipeActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    final side = _offset.value.sign;
    final lost =
        !_active ||
        (side < 0 && widget.trailing.isEmpty) ||
        (side > 0 && widget.leading.isEmpty);
    if (lost && _offset.value != 0) {
      _offset.value = 0;
      _setArmed(false, haptic: false);
      _group?.release(this);
    }
  }

  @override
  void dispose() {
    _scrolling?.removeListener(_onScrollingChanged);
    _group?.release(this);
    _offset.dispose();
    _expand.dispose();
    super.dispose();
  }

  void _onScrollingChanged() {
    if (_scrolling?.value == true && !_dragging && _offset.value != 0) {
      _close();
    }
  }

  List<SwipeAction> _actionsFor(double offset) =>
      offset < 0 ? widget.trailing : widget.leading;

  /// 某一側動作全部露出時的寬度。
  double _revealWidth(List<SwipeAction> actions) =>
      math.min(actions.length * _kActionWidth, _width * 0.8);

  /// 觸發完整滑動的距離：列寬 60%，且至少超過露出寬度半個按鈕，
  /// 避免動作多、螢幕窄時一展開就進入預備狀態。
  double _fullSwipeDistance(List<SwipeAction> actions) => math.max(
    _width * _kFullSwipeFraction,
    _revealWidth(actions) + _kActionWidth / 2,
  );

  void _animateOffset(double target, {Duration? duration}) {
    _offset.animateTo(
      target,
      duration: duration ?? AppMotion.spring,
      curve: duration == null ? AppMotion.springCurve : AppMotion.menuCurve,
    );
  }

  void _close() {
    _setArmed(false, haptic: false);
    _group?.release(this);
    if (_offset.value != 0) _animateOffset(0);
  }

  void _setArmed(bool armed, {bool haptic = true}) {
    if (_armed == armed) return;
    _armed = armed;
    if (armed) {
      if (haptic) HapticFeedback.lightImpact();
      _expand.forward();
    } else {
      _expand.reverse();
    }
  }

  void _onDragStart(DragStartDetails details) {
    _group?.activate(this);
    _offset.stop();
    _dragging = true;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final min = widget.trailing.isEmpty ? 0.0 : -_width;
    final max = widget.leading.isEmpty ? 0.0 : _width;
    final next = (_offset.value + details.delta.dx).clamp(min, max);
    _offset.value = next;
    final actions = _actionsFor(next);
    _setArmed(
      next != 0 &&
          actions.isNotEmpty &&
          next.abs() >= _fullSwipeDistance(actions),
    );
  }

  void _onDragEnd(DragEndDetails details) {
    _dragging = false;
    final offset = _offset.value;
    if (offset == 0) {
      _close();
      return;
    }
    final actions = _actionsFor(offset);
    if (_armed) {
      _runFullSwipe(offset, actions);
      return;
    }
    // 速度換算成「往展開方向」為正。
    final velocity = details.velocity.pixelsPerSecond.dx * offset.sign;
    final reveal = _revealWidth(actions);
    final open =
        velocity > _kFlingVelocity ||
        (velocity >= -_kFlingVelocity && offset.abs() > reveal / 2);
    if (open) {
      _animateOffset(reveal * offset.sign);
    } else {
      _close();
    }
  }

  void _onDragCancel() {
    _dragging = false;
    final offset = _offset.value;
    final actions = _actionsFor(offset);
    if (offset != 0 && offset.abs() > _revealWidth(actions) / 2) {
      _setArmed(false, haptic: false);
      _animateOffset(_revealWidth(actions) * offset.sign);
    } else {
      _close();
    }
  }

  Future<void> _runFullSwipe(double offset, List<SwipeAction> actions) async {
    final action = offset < 0 ? actions.last : actions.first;
    if (action.destructive) {
      await _offset
          .animateTo(
            _width * offset.sign,
            duration: AppMotion.menu,
            curve: AppMotion.menuCurve,
          )
          .orCancel
          .catchError((Object _) {});
      if (!mounted) return;
    }
    action.onPressed();
    if (mounted) _close();
  }

  void _onActionTap(SwipeAction action) {
    action.onPressed();
    if (mounted) _close();
  }

  @override
  Widget build(BuildContext context) {
    final active = _active;
    return LayoutBuilder(
      builder: (context, constraints) {
        _width = constraints.maxWidth;
        Widget row = AnimatedBuilder(
          animation: Listenable.merge([_offset, _expand]),
          child: widget.child,
          builder: (context, child) {
            final offset = _offset.value;
            final actions = _actionsFor(offset);
            return Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                if (offset != 0 && actions.isNotEmpty)
                  Positioned.fill(
                    child: _ActionStrip(
                      actions: actions,
                      trailing: offset < 0,
                      extent: offset.abs(),
                      expand: _expand.value,
                      onTap: _onActionTap,
                    ),
                  ),
                Transform.translate(
                  offset: Offset(offset, 0),
                  child: Stack(
                    children: [
                      child!,
                      // 展開時點列本身只收合，不觸發列的點擊。
                      if (offset != 0)
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            excludeFromSemantics: true,
                            onTap: _close,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
        row = RawGestureDetector(
          gestures: {
            if (active)
              HorizontalDragGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                    HorizontalDragGestureRecognizer
                  >(HorizontalDragGestureRecognizer.new, (recognizer) {
                    recognizer
                      ..onStart = _onDragStart
                      ..onUpdate = _onDragUpdate
                      ..onEnd = _onDragEnd
                      ..onCancel = _onDragCancel;
                  }),
          },
          child: row,
        );
        if (!active) return row;
        // 無障礙：不靠滑動也能從列的自訂動作選單執行。
        return Semantics(
          customSemanticsActions: {
            for (final action in [...widget.leading, ...widget.trailing])
              CustomSemanticsAction(label: action.label): action.onPressed,
          },
          child: row,
        );
      },
    );
  }
}

/// 露出區域內的動作按鈕列。
class _ActionStrip extends StatelessWidget {
  const _ActionStrip({
    required this.actions,
    required this.trailing,
    required this.extent,
    required this.expand,
    required this.onTap,
  });

  final List<SwipeAction> actions;
  final bool trailing;

  /// 露出寬度（px）。
  final double extent;

  /// 0–1：最外側動作撐滿露出區域的程度。
  final double expand;
  final ValueChanged<SwipeAction> onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final outer = trailing ? actions.length - 1 : 0;
        final base = extent / actions.length;
        var left = trailing ? width - extent : 0.0;
        final children = <Widget>[];
        for (var i = 0; i < actions.length; i++) {
          // 未滑過列寬時平均分配露出寬度；預備完整滑動時最外側動作吃掉其他格。
          final w =
              i == outer
                  ? base + (extent - base) * expand
                  : base * (1 - expand);
          children.add(
            Positioned(
              left: left,
              top: 0,
              bottom: 0,
              width: w,
              child: _ActionButton(
                action: actions[i],
                onTap: () => onTap(actions[i]),
              ),
            ),
          );
          left += w;
        }
        return Stack(children: children);
      },
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.action, required this.onTap});

  final SwipeAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const foreground = AppPalette.paper50;
    return Semantics(
      button: true,
      label: action.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ColoredBox(
          color: action.color,
          child: ClipRect(
            child: OverflowBox(
              minWidth: _kActionWidth,
              maxWidth: _kActionWidth,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(action.icon, size: 22, color: foreground),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    action.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.uiXs.copyWith(color: foreground),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
