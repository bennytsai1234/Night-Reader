import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/glass.dart';

/// 閱讀選單一塊（上方選單、下方選單、亮度條）的進場與收起：從 [edge]
/// 那一側滑入（[AppMotion.readerMenuIn]，減速），收起時滑出
/// （[AppMotion.readerMenuOut]，加速）。只滑動不淡入（ADR 0022）：選單是
/// 玻璃，淡入時模糊到最後一幀才突然糊上去。[delay] 只用在進場，讓幾塊錯開
/// 出發。
///
/// 自己聽 [visible]，選單開關時只有滑動與擋點擊這兩層跟著變，[child]
/// （按鈕、章名、進度條、亮度條）不重建（ADR 0029 做法 3）。收起時不接
/// 點擊；系統關閉動畫時直接到位。
class ReaderV2MenuEntrance extends StatefulWidget {
  const ReaderV2MenuEntrance({
    super.key,
    required this.visible,
    required this.edge,
    this.gap = 0,
    this.delay = Duration.zero,
    this.onHidden,
    required this.child,
  });

  final ValueListenable<bool> visible;

  /// 從哪一側滑出去。
  final AxisDirection edge;

  /// 這一塊離 [edge] 那側螢幕邊緣的距離（見 [GlassSlide.gap]）。
  final double gap;
  final Duration delay;

  /// 收起動畫播完、這一塊完全移出畫面時呼叫（系統關閉動畫時在收起的
  /// 那一幀）。
  final VoidCallback? onHidden;
  final Widget child;

  @override
  State<ReaderV2MenuEntrance> createState() => _ReaderV2MenuEntranceState();
}

class _ReaderV2MenuEntranceState extends State<ReaderV2MenuEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.readerMenuIn + widget.delay,
    reverseDuration: AppMotion.readerMenuOut,
    value: widget.visible.value ? 1 : 0,
  )..addStatusListener(_onStatus);

  late final CurvedAnimation _progress = CurvedAnimation(
    parent: _controller,
    curve: Interval(_delayFraction, 1, curve: Curves.easeOutCubic),
    reverseCurve: Curves.easeInCubic.flipped,
  );

  bool _reduceMotion = false;

  double get _delayFraction {
    final total = AppMotion.readerMenuIn + widget.delay;
    return widget.delay.inMicroseconds / total.inMicroseconds;
  }

  @override
  void initState() {
    super.initState();
    widget.visible.addListener(_onVisibleChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
  }

  void _onStatus(AnimationStatus status) {
    if (status.isDismissed) widget.onHidden?.call();
  }

  @override
  void didUpdateWidget(ReaderV2MenuEntrance oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(widget.visible, oldWidget.visible)) return;
    oldWidget.visible.removeListener(_onVisibleChanged);
    widget.visible.addListener(_onVisibleChanged);
    _onVisibleChanged();
  }

  void _onVisibleChanged() {
    final visible = widget.visible.value;
    if (_reduceMotion) {
      _controller.value = visible ? 1 : 0;
    } else if (visible) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    widget.visible.removeListener(_onVisibleChanged);
    _progress.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: widget.visible,
      builder: (context, visible, child) =>
          IgnorePointer(ignoring: !visible, child: child),
      child: AnimatedBuilder(
        animation: _progress,
        child: widget.child,
        builder: (context, child) => GlassSlide(
          shown: _progress.value,
          edge: widget.edge,
          gap: widget.gap,
          child: child!,
        ),
      ),
    );
  }
}
