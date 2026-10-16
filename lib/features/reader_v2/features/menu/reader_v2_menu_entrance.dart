import 'package:flutter/material.dart';
import 'package:night_reader/core/services/motion_gate.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';

/// 閱讀選單一塊（上方選單、下方選單、亮度條）的進場與收起：從 [hiddenOffset]
/// 那一側滑入並淡入（[AppMotion.readerMenuIn]，減速），收起時滑出並淡出
/// （[AppMotion.readerMenuOut]，加速）。[delay] 只用在進場，讓幾塊錯開出發。
///
/// 播放中持有 [MotionGate]（ADR 0018），背景下載不會在這幾幀解析章節。
/// 收起時不接點擊；系統關閉動畫時直接到位。
class ReaderV2MenuEntrance extends StatefulWidget {
  const ReaderV2MenuEntrance({
    super.key,
    required this.visible,
    required this.hiddenOffset,
    this.delay = Duration.zero,
    required this.child,
  });

  final bool visible;

  /// 收起時的位移，以自身大小為單位；多移出一段，讓浮動玻璃的漫射陰影
  /// 也一起離開畫面。
  final Offset hiddenOffset;
  final Duration delay;
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
    value: widget.visible ? 1 : 0,
  )..addStatusListener(_onStatus);

  late final CurvedAnimation _progress = CurvedAnimation(
    parent: _controller,
    curve: Interval(_delayFraction, 1, curve: Curves.easeOutCubic),
    reverseCurve: Curves.easeInCubic.flipped,
  );

  late final Animation<Offset> _slide = Tween<Offset>(
    begin: widget.hiddenOffset,
    end: Offset.zero,
  ).animate(_progress);

  final MotionHold _hold = MotionHold();

  double get _delayFraction {
    final total = AppMotion.readerMenuIn + widget.delay;
    return widget.delay.inMicroseconds / total.inMicroseconds;
  }

  void _onStatus(AnimationStatus status) {
    _hold.moving = status.isAnimating;
  }

  @override
  void didUpdateWidget(ReaderV2MenuEntrance oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible == oldWidget.visible) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = widget.visible ? 1 : 0;
    } else if (widget.visible) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _hold.release();
    _progress.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !widget.visible,
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(opacity: _progress, child: widget.child),
      ),
    );
  }
}
