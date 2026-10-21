import 'package:flutter/material.dart';

/// 點擊區：按下時在所在的 [Material] 上畫一層高亮，點了呼叫 [onTap]。
///
/// 高亮和 [InkWell] 按下時的一樣（同一種 [InkHighlight]、同樣 200ms 淡入
/// 淡出，主題的水波紋在這個 App 是 [NoSplash]，本來就不畫），點擊與長按的
/// 回饋（[Feedback]）也一樣。少的是 InkWell 每一個都帶的鍵盤焦點（Focus、
/// Actions）、滑鼠懸停與狀態控制器：分組清單一列一個、步進列一列三個，閱讀
/// 偏好一進頁要建三十幾個，是換頁第一格最大的一塊，而這個 App 只在手機上用
/// 手指點，讀屏走 Semantics 的點擊動作（ADR 0029）。
class PressInk extends StatefulWidget {
  const PressInk({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.highlightColor,
    this.borderRadius,
    this.customBorder,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// 按下的高亮；null 時用主題的 [ThemeData.highlightColor]（和 InkWell
  /// 一樣）。
  final Color? highlightColor;
  final BorderRadius? borderRadius;
  final ShapeBorder? customBorder;

  @override
  State<PressInk> createState() => _PressInkState();
}

class _PressInkState extends State<PressInk>
    with AutomaticKeepAliveClientMixin<PressInk> {
  InkHighlight? _highlight;

  bool get _enabled => widget.onTap != null || widget.onLongPress != null;

  /// 高亮還在（按著或正在淡出）時，清單捲動也不拆掉這一列。
  @override
  bool get wantKeepAlive => _highlight != null;

  void _setPressed(bool pressed) {
    final highlight = _highlight;
    if (pressed == (highlight != null && highlight.active)) return;
    if (!pressed) {
      highlight!.deactivate();
      return;
    }
    if (highlight != null) {
      highlight.activate();
      return;
    }
    final referenceBox = context.findRenderObject()! as RenderBox;
    _highlight = InkHighlight(
      controller: Material.of(context),
      referenceBox: referenceBox,
      color: widget.highlightColor ?? Theme.of(context).highlightColor,
      borderRadius: widget.borderRadius,
      customBorder: widget.customBorder,
      onRemoved: () {
        _highlight = null;
        updateKeepAlive();
      },
      textDirection: Directionality.of(context),
      fadeDuration: const Duration(milliseconds: 200),
    );
    updateKeepAlive();
  }

  void _handleTap() {
    _setPressed(false);
    final onTap = widget.onTap;
    if (onTap == null) return;
    Feedback.forTap(context);
    onTap();
  }

  void _handleLongPress() {
    final onLongPress = widget.onLongPress;
    if (onLongPress == null) return;
    Feedback.forLongPress(context);
    onLongPress();
  }

  /// 讀屏的點擊：照手指點的樣子閃一下高亮再點。
  void _simulateTap() {
    _setPressed(true);
    _handleTap();
  }

  @override
  void didUpdateWidget(PressInk oldWidget) {
    super.didUpdateWidget(oldWidget);
    final highlight = _highlight;
    if (highlight == null) return;
    highlight
      ..color = widget.highlightColor ?? Theme.of(context).highlightColor
      ..customBorder = widget.customBorder;
    if (!_enabled) _setPressed(false);
  }

  @override
  void deactivate() {
    _highlight?.dispose();
    _highlight = null;
    super.deactivate();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final enabled = _enabled;
    return Semantics(
      onTap: widget.onTap == null ? null : _simulateTap,
      onLongPress: widget.onLongPress == null ? null : _handleLongPress,
      child: GestureDetector(
        onTapDown: enabled ? (_) => _setPressed(true) : null,
        onTap: enabled ? _handleTap : null,
        onTapCancel: enabled ? () => _setPressed(false) : null,
        onLongPress: widget.onLongPress == null ? null : _handleLongPress,
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        child: widget.child,
      ),
    );
  }
}
