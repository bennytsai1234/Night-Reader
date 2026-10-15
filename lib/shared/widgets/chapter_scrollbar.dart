import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/glass.dart';

/// 長目錄的快速捲軸（取法 Telegram Android 的 fast scroller）：清單捲動時
/// 右緣浮出一顆細長的拖曳鈕，停下一會兒後淡出；按住拖動時依位置跳到對應的
/// 章節，左邊浮出那一章的名稱。目錄不到幾個畫面長時不出現。
///
/// 只聽 [child] 最外層的捲動；位置一律以章節序號換算（目錄前面還有其他
/// 內容時，拖到最上面就是第一章）。
class ChapterScrollbar extends StatefulWidget {
  const ChapterScrollbar({
    super.key,
    required this.itemCount,
    required this.visibleRange,
    required this.onJumpTo,
    required this.labelFor,
    required this.child,
    this.padding = EdgeInsets.zero,
  });

  final int itemCount;

  /// 目前畫面上第一列與最後一列的序號；目錄還沒出現在畫面上時為 null。
  final (int, int)? Function() visibleRange;

  /// 把第 [index] 列捲到畫面上緣（頁首下方）。
  final ValueChanged<int> onJumpTo;
  final String Function(int index) labelFor;
  final Widget child;

  /// 拖曳軌道上下讓出的距離（玻璃頁首、底部浮動鈕、系統手勢列）。
  final EdgeInsets padding;

  @override
  State<ChapterScrollbar> createState() => _ChapterScrollbarState();
}

class _ChapterScrollbarState extends State<ChapterScrollbar> {
  /// 清單至少這麼多個畫面長才出現；更短的目錄直接滑就到了。
  static const double _minScreens = 4;

  /// 停止捲動後多久淡出，同 Telegram Android。
  static const Duration _hideDelay = Duration(milliseconds: 1500);
  static const double _thumbHeight = 44;
  static const double _thumbWidth = 6;
  static const double _touchWidth = 32;

  bool _long = false;
  bool _visible = false;
  bool _dragging = false;

  /// 拖曳鈕在軌道上的位置（0 頂、1 底）。
  double _fraction = 0;
  int _dragIndex = 0;
  Timer? _hideTimer;

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  int get _span {
    final range = widget.visibleRange();
    if (range == null) return 1;
    return math.max(1, range.$2 - range.$1 + 1);
  }

  /// 拖到底時停在最後一頁：最上面那一列是倒數第 [_span] 列。
  int get _lastTopIndex => math.max(0, widget.itemCount - _span);

  bool _handleScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    final metrics = notification.metrics;
    final long =
        widget.itemCount > 1 &&
        metrics.maxScrollExtent > metrics.viewportDimension * _minScreens;
    if (long != _long) setState(() => _long = long);
    if (!long || _dragging) return false;
    if (notification is ScrollUpdateNotification) {
      final first = widget.visibleRange()?.$1 ?? 0;
      final last = _lastTopIndex;
      setState(() {
        _visible = true;
        _fraction = last <= 0 ? 0 : (first / last).clamp(0.0, 1.0);
      });
      _scheduleHide();
    }
    return false;
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_hideDelay, () {
      if (mounted && !_dragging) setState(() => _visible = false);
    });
  }

  void _dragTo(double fraction) {
    final clamped = fraction.clamp(0.0, 1.0).toDouble();
    final index = (clamped * _lastTopIndex).round();
    setState(() {
      _fraction = clamped;
      _dragIndex = index;
    });
    widget.onJumpTo(index);
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _handleScroll,
      child: Stack(
        children: [
          widget.child,
          if (_long)
            Positioned(
              top: widget.padding.top,
              bottom: widget.padding.bottom,
              right: 0,
              left: 0,
              child: IgnorePointer(
                ignoring: !_visible,
                child: AnimatedOpacity(
                  opacity: _visible ? 1 : 0,
                  duration: AppMotion.fade,
                  curve: AppMotion.fadeCurve,
                  child: LayoutBuilder(builder: _buildTrack),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTrack(BuildContext context, BoxConstraints constraints) {
    final scheme = Theme.of(context).colorScheme;
    final travel = math.max(0.0, constraints.maxHeight - _thumbHeight);
    final top = travel * _fraction;
    return Stack(
      children: [
        // 有 key：泡泡插進來時拖曳鈕的元件不能被換掉，否則拖到一半手勢就斷了。
        if (_dragging)
          Positioned(
            key: const ValueKey('bubble'),
            top: top + (_thumbHeight - AppGlass.buttonSize) / 2,
            right: _touchWidth + AppSpacing.xs,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: math.min(260, constraints.maxWidth * 0.7),
              ),
              child: SizedBox(
                height: AppGlass.buttonSize,
                child: GlassSurface(
                  borderRadius: AppRadius.pillShape,
                  grouped: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                    ),
                    child: Center(
                      widthFactor: 1,
                      child: Text(
                        widget.labelFor(_dragIndex),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.uiMd.copyWith(
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        Positioned(
          key: const ValueKey('thumb'),
          top: top,
          right: 0,
          width: _touchWidth,
          height: _thumbHeight,
          child: Semantics(
            label: '快速捲動目錄',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragStart: (_) {
                _hideTimer?.cancel();
                setState(() {
                  _dragging = true;
                  _dragIndex = (_fraction * _lastTopIndex).round();
                });
              },
              onVerticalDragUpdate: (details) {
                if (travel <= 0) return;
                _dragTo(_fraction + details.delta.dy / travel);
              },
              onVerticalDragEnd: (_) => _endDrag(),
              onVerticalDragCancel: _endDrag,
              child: Center(
                child: AnimatedContainer(
                  duration: AppMotion.menu,
                  curve: AppMotion.menuCurve,
                  width: _dragging ? _thumbWidth + 2 : _thumbWidth,
                  height: _thumbHeight,
                  decoration: BoxDecoration(
                    color: _dragging
                        ? scheme.primary
                        : scheme.onSurfaceVariant.withValues(alpha: 0.5),
                    borderRadius: AppRadius.pillShape,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _endDrag() {
    if (!_dragging) return;
    setState(() => _dragging = false);
    _scheduleHide();
  }
}
