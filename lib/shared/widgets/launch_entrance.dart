import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import 'glass.dart';
import 'skeleton.dart';
import 'skeleton_reveal.dart';

/// 開 App 的進場（ADR 0025）：系統啟動畫面只有底色，Flutter 第一幀也只畫
/// 底色；接著整個畫面照骨架換場（[SkeletonReveal]）的方式與時長長出骨架：
/// 書架、頁首的標題與兩側按鈕、底部分頁列（書架以外用 [LaunchSkeleton]）。
/// 骨架呼吸著等書架準備好（書、封面、書名的繁簡轉換），書架換場時標題、
/// 按鈕與分頁列跟著同一段換成真的（[LaunchEntranceMotion.reveal]）。
///
/// 包在主頁面外面；底下的頁首（`GlassNavHeader`）、分頁列與書架用
/// [maybeOf] 取得各自的進度。從主頁面推出去的頁面不在底下，不受影響。
/// 系統要求減少動態時骨架直接到位。
class LaunchEntrance extends StatefulWidget {
  const LaunchEntrance({super.key, required this.child});

  final Widget child;

  static LaunchEntranceMotion? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_LaunchEntranceScope>()
      ?.motion;

  @override
  State<LaunchEntrance> createState() => _LaunchEntranceState();
}

/// 進場各部分的進度，0 還沒出現、1 到位。
class LaunchEntranceMotion {
  LaunchEntranceMotion._(this._controller, {required this.sweep}) {
    skeleton = CurvedAnimation(parent: _controller, curve: AppMotion.fadeCurve);
  }

  final AnimationController _controller;

  /// 骨架出現；完成時才讀進書架的內容。
  late final Animation<double> skeleton;

  /// 骨架出現是不是由左而右。
  final bool sweep;

  /// 書架換成內容的進度（套過曲線）：書架開始換場前是 0，換完之後一直是 1。
  /// 由書架的 `SkeletonSwitcher` 用 [revealWith] 接上。
  Animation<double> get reveal => _reveal;
  final ProxyAnimation _reveal = ProxyAnimation(kAlwaysDismissedAnimation);

  /// 書架換場是不是由左而右。
  bool get revealSweep => _revealSweep;
  bool _revealSweep = false;

  /// 整段進場（骨架出現到換成內容）已經結束。
  bool get done => _reveal.parent == kAlwaysCompleteAnimation;

  /// 書架第一次換成內容時呼叫：按鈕與分頁列跟著 [progress] 換成玻璃。之後
  /// 書架重新載入不再影響它們。
  void revealWith(Animation<double> progress, {required bool sweep}) {
    if (_reveal.parent != kAlwaysDismissedAnimation) return;
    _revealSweep = sweep;
    if (progress.isCompleted) {
      _reveal.parent = kAlwaysCompleteAnimation;
      return;
    }
    _reveal.parent = progress;
    void onStatus(AnimationStatus status) {
      if (!status.isCompleted) return;
      progress.removeStatusListener(onStatus);
      _reveal.parent = kAlwaysCompleteAnimation;
    }

    progress.addStatusListener(onStatus);
  }
}

class _LaunchEntranceState extends State<LaunchEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);
  LaunchEntranceMotion? _motion;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_motion != null) return;
    // 方式與時長在第一次建畫面時定下來，播放中改設定不影響這一次。
    final reveal = SkeletonReveal.of(context);
    _controller.duration = reveal.duration;
    _motion = LaunchEntranceMotion._(_controller, sweep: reveal.sweeps);
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
      return;
    }
    // 第一幀只畫底色、和系統啟動畫面一樣，畫完才開始進場。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _LaunchEntranceScope(motion: _motion!, child: widget.child);
}

class _LaunchEntranceScope extends InheritedWidget {
  const _LaunchEntranceScope({required this.motion, required super.child});

  final LaunchEntranceMotion motion;

  @override
  bool updateShouldNotify(_LaunchEntranceScope oldWidget) =>
      !identical(motion, oldWidget.motion);
}

/// 開 App 進場時，頁首與分頁列的一個元件先畫成骨架，和書架的骨架一起
/// 出現、一起呼吸；書架換場時骨架淡掉、元件出現。由左而右時照元件中心的
/// 橫向位置決定先後，和書架的掃動對齊。
///
/// - 玻璃（頁首按鈕、分頁列、搜尋鈕）：骨架照它的大小與 [borderRadius] 畫
///   （圓鈕就是最窄的膠囊），玻璃連同模糊一起淡入（[GlassReveal]，ADR 0022）。
/// - 一行字（[LaunchSkeleton.text]，頁首標題）：骨架是和字同寬、約字身高
///   的長條（同 [SkeletonLine]），字只淡入。
///
/// 出現前不接點擊、不給讀屏念。不在進場底下，或進場結束後才建的（例如
/// 之後才打開的分頁），直接畫 [child]。
class LaunchSkeleton extends StatefulWidget {
  const LaunchSkeleton({
    super.key,
    this.borderRadius = AppRadius.pillShape,
    required this.child,
  }) : textStyle = null;

  const LaunchSkeleton.text({
    super.key,
    required TextStyle this.textStyle,
    required this.child,
  }) : borderRadius = AppRadius.cardXs;

  final BorderRadius borderRadius;

  /// [child] 是一行這個樣式的字；null 時 [child] 是一塊玻璃。
  final TextStyle? textStyle;
  final Widget child;

  @override
  State<LaunchSkeleton> createState() => _LaunchSkeletonState();
}

class _LaunchSkeletonState extends State<LaunchSkeleton> {
  /// 這個元件中心在螢幕上的橫向位置（0 左緣、1 右緣）；量到之前骨架還沒
  /// 開始出現，先取中央。
  double _u = 0.5;

  /// 照 [_u] 換算的濃度；跟著書架換場走。
  late final Animation<double> _glass = _SweptAnimation(
    parent: _motion!.reveal,
    opacityAt: (progress) => SkeletonReveal.incomingOpacityAt(
      progress,
      _u,
      sweep: _motion!.revealSweep,
    ),
  );

  LaunchEntranceMotion? _motion;

  /// 建立時進場已經結束（或不在進場底下）：一直直接畫。
  bool _passThrough = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final motion = LaunchEntrance.maybeOf(context);
    if (_motion == null) {
      _motion = motion;
      _passThrough = motion == null || motion.done;
    }
    if (_passThrough || _motion!.done) return;
    // 螢幕大小改變時（登記在這裡）重新量位置。
    MediaQuery.sizeOf(context);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  void _measure() {
    if (!mounted) return;
    final box = context.findRenderObject();
    final width = MediaQuery.sizeOf(context).width;
    if (box is! RenderBox || !box.hasSize || width <= 0) return;
    final center = box.localToGlobal(box.size.center(Offset.zero));
    _u = (center.dx / width).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final motion = _motion;
    if (_passThrough || motion == null) return widget.child;
    final style = widget.textStyle;
    final child = style == null
        ? GlassReveal(animation: _glass, child: widget.child)
        : FadeTransition(opacity: _glass, child: widget.child);
    // 字的骨架是一條約字身高的長條，置中在那一行上。
    final barHeight = style == null
        ? null
        : MediaQuery.textScalerOf(context).scale(style.fontSize ?? 14) * 0.75;
    return AnimatedBuilder(
      animation: Listenable.merge([motion.skeleton, motion.reveal]),
      child: child,
      builder: (context, child) {
        final done = motion.done || motion.reveal.isCompleted;
        // 玻璃出現前不接點擊、不給讀屏念；元件樹一直相同，按鈕的狀態不丟。
        final hidden = !done;
        final appeared = SkeletonReveal.incomingOpacityAt(
          motion.skeleton.value,
          _u,
          sweep: motion.sweep,
        );
        final skeleton = appeared * (1 - _glass.value);
        final base = Skeleton.colorOf(context);
        return Stack(
          fit: StackFit.passthrough,
          children: [
            IgnorePointer(
              ignoring: hidden,
              child: ExcludeSemantics(excluding: hidden, child: child),
            ),
            if (!done)
              Positioned.fill(
                child: IgnorePointer(
                  child: Center(
                    child: Skeleton(
                      child: SkeletonBox(
                        width: double.infinity,
                        height: barHeight ?? double.infinity,
                        borderRadius: widget.borderRadius,
                        color: base.withValues(alpha: base.a * skeleton),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 把 [parent] 的進度換算成某個位置上的濃度。
class _SweptAnimation extends Animation<double>
    with AnimationWithParentMixin<double> {
  _SweptAnimation({required this.parent, required this.opacityAt});

  @override
  final Animation<double> parent;

  final double Function(double progress) opacityAt;

  @override
  double get value => opacityAt(parent.value);
}
