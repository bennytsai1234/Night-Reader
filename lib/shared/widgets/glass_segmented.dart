import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme/app_chrome.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_tokens.dart';

/// [GlassSegmented] 的單一分段。
@immutable
class GlassSegment<T> {
  const GlassSegment(this.value, this.label, {this.icon});

  final T value;
  final String label;
  final IconData? icon;
}

/// Telegram 式分段控制：膠囊軌道上滑動的選取塊。
///
/// 單選，取代 Material [SegmentedButton] 的單選用法。[selected] 不在
/// [segments] 中時（例如舊版寫入的非選項值）不顯示選取塊，也不選取任何分段。
/// 點擊分段切換；按住選取塊可左右拖動，放開時對齊最近的分段。
///
/// 為受控元件：只透過 [onChanged] 回報，選取塊最終位置以 [selected] 為準。
class GlassSegmented<T> extends StatefulWidget {
  const GlassSegmented({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
    this.expand = true,
  }) : assert(segments.length > 0);

  final List<GlassSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  /// true 時撐滿可用寬度；false 時以最寬標籤決定等寬分段的寬度。
  final bool expand;

  @override
  State<GlassSegmented<T>> createState() => _GlassSegmentedState<T>();
}

/// 軌道高度與選取塊內縮（Telegram 36pt 膠囊、2pt 內縮）。
const double _kTrackHeight = 36.0;
const double _kThumbInset = 2.0;

class _GlassSegmentedState<T> extends State<GlassSegmented<T>>
    with SingleTickerProviderStateMixin {
  /// 選取塊位置，以分段索引為單位（可為小數）。
  late final AnimationController _position;

  /// 拖動中的選取塊位置；null 表示沒有在拖動。
  double? _dragPosition;

  int? get _selectedIndex {
    final index = widget.segments.indexWhere((s) => s.value == widget.selected);
    return index < 0 ? null : index;
  }

  @override
  void initState() {
    super.initState();
    _position = AnimationController.unbounded(
      vsync: this,
      value: (_selectedIndex ?? 0).toDouble(),
    );
  }

  @override
  void didUpdateWidget(GlassSegmented<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldIndex = oldWidget.segments.indexWhere(
      (s) => s.value == oldWidget.selected,
    );
    final index = _selectedIndex;
    if (index == null) return;
    if (oldIndex < 0) {
      // 從「無選取」變成有選取：選取塊直接出現在目標位置，不從舊位置滑入。
      _position.value = index.toDouble();
      _target = index;
    } else {
      _animateTo(index);
    }
  }

  @override
  void dispose() {
    _position.dispose();
    super.dispose();
  }

  /// 目前動畫的目標索引；避免同一目標重新起跑而打斷彈簧曲線。
  int? _target;

  void _animateTo(int index) {
    if (_dragPosition != null) return;
    if (_position.isAnimating ? _target == index : _position.value == index) {
      return;
    }
    _target = index;
    _position.animateTo(
      index.toDouble(),
      duration: AppMotion.spring,
      curve: AppMotion.springCurve,
    );
  }

  double _segmentWidth() {
    final width = (context.size?.width ?? 0) - _kThumbInset * 2;
    return width / widget.segments.length;
  }

  int _indexAt(double dx) {
    final segment = _segmentWidth();
    if (segment <= 0) return 0;
    return ((dx - _kThumbInset) / segment).floor().clamp(
      0,
      widget.segments.length - 1,
    );
  }

  void _select(int index) {
    final value = widget.segments[index].value;
    if (value != widget.selected) widget.onChanged(value);
    // 呼叫端沒有採用新值時，選取塊回到 [selected] 的位置。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final current = _selectedIndex;
      if (current != null) _animateTo(current);
    });
  }

  void _onDragStart(DragStartDetails details) {
    final index = _selectedIndex;
    // 只有從選取塊上開始的拖動才移動選取塊。
    if (index == null || _indexAt(details.localPosition.dx) != index) return;
    _position.stop();
    setState(() => _dragPosition = _position.value);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final start = _dragPosition;
    final segment = _segmentWidth();
    if (start == null || segment <= 0) return;
    final next = (start + details.delta.dx / segment).clamp(
      0.0,
      (widget.segments.length - 1).toDouble(),
    );
    _position.value = next;
    setState(() => _dragPosition = next);
  }

  void _onDragEnd(DragEndDetails details) {
    final end = _dragPosition;
    if (end == null) return;
    setState(() => _dragPosition = null);
    final target = end.round();
    _animateTo(target);
    _select(target);
  }

  void _onDragCancel() {
    if (_dragPosition == null) return;
    setState(() => _dragPosition = null);
    final index = _selectedIndex;
    if (index != null) _animateTo(index);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final chrome = AppChrome.of(context);
    final isLight = theme.brightness == Brightness.light;
    final track = Color.alphaBlend(
      chrome.pressedHighlight,
      chrome.groupedSurface,
    );
    final thumb =
        isLight
            ? chrome.groupedSurface
            : Color.alphaBlend(
              scheme.onSurface.withValues(alpha: 0.14),
              chrome.groupedSurface,
            );
    final selectedIndex = _selectedIndex;
    // 拖動中以選取塊所在的分段顯示粗體，放開前就能看出會落在哪一段。
    final emphasized = _dragPosition?.round() ?? selectedIndex;

    Widget row = Row(
      children: [
        for (var i = 0; i < widget.segments.length; i++)
          Expanded(
            child: _SegmentLabel(
              segment: widget.segments[i],
              selected: i == selectedIndex,
              emphasized: i == emphasized,
              color: scheme.onSurface,
              onTap: () => _select(i),
            ),
          ),
      ],
    );
    if (!widget.expand) row = IntrinsicWidth(child: row);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // 語意由各分段提供，外層不再暴露一個整體的點擊動作。
      excludeFromSemantics: true,
      // 以按下位置判斷是否從選取塊開始拖動，並讓選取塊跟上觸控斜率內的位移。
      dragStartBehavior: DragStartBehavior.down,
      onTapUp: (details) => _select(_indexAt(details.localPosition.dx)),
      onHorizontalDragStart: _onDragStart,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      onHorizontalDragCancel: _onDragCancel,
      child: SizedBox(
        height: _kTrackHeight,
        child: CustomPaint(
          painter: _TrackPainter(
            position: _position,
            count: widget.segments.length,
            visible: selectedIndex != null,
            pressed: _dragPosition != null,
            trackColor: track,
            thumbColor: thumb,
            shadowColor: chrome.glassShadow,
          ),
          child: Padding(
            padding: const EdgeInsets.all(_kThumbInset),
            child: row,
          ),
        ),
      ),
    );
  }
}

class _SegmentLabel extends StatelessWidget {
  const _SegmentLabel({
    required this.segment,
    required this.selected,
    required this.emphasized,
    required this.color,
    required this.onTap,
  });

  final GlassSegment<Object?> segment;
  final bool selected;
  final bool emphasized;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = AppTextStyles.uiSm.copyWith(
      color: color,
      fontWeight: emphasized ? FontWeight.w600 : FontWeight.w500,
    );
    final text = Text(
      segment.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: style,
    );
    final icon = segment.icon;
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: Center(
          child:
              icon == null
                  ? text
                  : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 16, color: color),
                      const SizedBox(width: AppSpacing.xs),
                      Flexible(child: text),
                    ],
                  ),
        ),
      ),
    );
  }
}

/// 畫膠囊軌道與選取塊；選取塊位置跟著 [position] 重繪，不重建子樹。
class _TrackPainter extends CustomPainter {
  _TrackPainter({
    required this.position,
    required this.count,
    required this.visible,
    required this.pressed,
    required this.trackColor,
    required this.thumbColor,
    required this.shadowColor,
  }) : super(repaint: position);

  final Animation<double> position;
  final int count;
  final bool visible;
  final bool pressed;
  final Color trackColor;
  final Color thumbColor;
  final Color shadowColor;

  @override
  void paint(Canvas canvas, Size size) {
    final trackRadius = Radius.circular(size.height / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, trackRadius),
      Paint()..color = trackColor,
    );
    if (!visible || count == 0) return;
    final segment = (size.width - _kThumbInset * 2) / count;
    var rect = Rect.fromLTWH(
      _kThumbInset + segment * position.value,
      _kThumbInset,
      segment,
      size.height - _kThumbInset * 2,
    );
    if (pressed) {
      // 拖動時選取塊略為放大，表示已被拿起。
      rect = rect.inflate(1);
    }
    final thumb = RRect.fromRectAndRadius(
      rect,
      Radius.circular(rect.height / 2),
    );
    final shadow =
        BoxShadow(color: shadowColor, blurRadius: 6).toPaint();
    canvas.drawRRect(thumb.shift(const Offset(0, 2)), shadow);
    canvas.drawRRect(thumb, Paint()..color = thumbColor);
  }

  @override
  bool shouldRepaint(_TrackPainter oldDelegate) =>
      oldDelegate.position != position ||
      oldDelegate.count != count ||
      oldDelegate.visible != visible ||
      oldDelegate.pressed != pressed ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.thumbColor != thumbColor ||
      oldDelegate.shadowColor != shadowColor;
}
