import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../theme/app_tokens.dart';
import 'skeleton.dart';
import 'skeleton_reveal.dart';
import 'snapshot_sweep.dart';

/// 開 App 的進場（ADR 0025）：系統啟動畫面只有底色，Flutter 第一幀也只畫
/// 底色；接著整個畫面照骨架換場（[SkeletonReveal]）的方式與時長長出骨架：
/// 書架、頁首的標題與兩側按鈕、底部分頁列（書架以外用 [LaunchSkeleton]）。
/// 骨架呼吸著等書架準備好（書、封面、書名的繁簡轉換），書架換場時整個畫面
/// 一起換成真的：換場前把骨架畫面與換好的畫面各畫成一張圖，換場的 0.6 秒
/// 只把兩張圖照每個像素的橫向位置混合（[SnapshotSweep]，ADR 0029），頁首、
/// 分頁列與書架照同一條曲線由左而右換過去。
///
/// 包在主頁面外面；底下的頁首（`GlassNavHeader`）、分頁列與書架用
/// [maybeOf] 取得進場的狀態。從主頁面推出去的頁面不在底下，不受影響。
/// 系統要求減少動態時骨架直接到位、換場直接換好。
class LaunchEntrance extends StatefulWidget {
  const LaunchEntrance({super.key, required this.child, this.onFinished});

  final Widget child;

  /// 整段進場結束時呼叫一次：開 App 的背景工作從這裡才開始，不和進場搶
  /// 主執行緒（ADR 0018）。
  final VoidCallback? onFinished;

  static LaunchEntranceMotion? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_LaunchEntranceScope>()
      ?.motion;

  @override
  State<LaunchEntrance> createState() => _LaunchEntranceState();
}

/// 進場的狀態。
class LaunchEntranceMotion {
  LaunchEntranceMotion._(this._controller, {required this.sweep});

  final AnimationController _controller;

  /// 骨架出現的進度（經過的時間比例，曲線由 [SkeletonReveal] 套）；完成時才
  /// 讀進書架的內容。
  Animation<double> get skeleton => _controller;

  /// 骨架出現是不是由左而右。
  final bool sweep;

  /// 整個主頁面的定格換場，書架第一次換成內容時用（[reveal]）。
  final SnapshotSweepController screen = SnapshotSweepController();

  /// 頁首按鈕、標題與分頁列已經換成真的（[LaunchSkeleton] 聽它）；一旦換了
  /// 就一直是 true，之後書架重新載入不再影響它們。
  ValueListenable<bool> get revealed => _revealed;
  final ValueNotifier<bool> _revealed = ValueNotifier(false);

  /// 書架第一次換成內容已經開始（[reveal] 或 [revealNow]）。
  bool get revealStarted => _revealStarted;
  bool _revealStarted = false;

  /// 整段進場（骨架出現到換成內容）已經結束。
  bool get done => _finished.isCompleted;

  /// 整段進場結束時完成。
  Future<void> get finished => _finished.future;
  final Completer<void> _finished = Completer<void>();

  /// 書架第一次換成內容：[change] 把書架換成內容，頁首按鈕、標題與分頁列
  /// 同時換成真的，整個畫面照 [screen] 換場（[sweep] 時由左而右）；播完才算
  /// 整段進場結束。之後再呼叫（書架重新載入）只做 [change]。
  Future<void> reveal({
    required VoidCallback change,
    required Duration duration,
    required bool sweep,
  }) async {
    if (_revealStarted) {
      change();
      return;
    }
    _revealStarted = true;
    await screen.play(
      duration: duration,
      sweep: sweep,
      change: () {
        change();
        _revealed.value = true;
      },
    );
    _finish();
  }

  /// 書架一開始就是內容（沒有骨架可換）：按鈕也直接到位。
  void revealNow() {
    if (_revealStarted) return;
    _revealStarted = true;
    _revealed.value = true;
    _finish();
  }

  void _finish() {
    if (!_finished.isCompleted) _finished.complete();
  }

  void _dispose() => _revealed.dispose();
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
    final motion = _motion = LaunchEntranceMotion._(
      _controller,
      sweep: reveal.sweeps,
    );
    // 換場最後一幀還在畫時就會完成；等這一幀畫完才開始背景工作，最後一幀
    // 不必跟著等它同步的那一段。
    unawaited(
      motion.finished.then((_) => SchedulerBinding.instance.endOfFrame).then((
        _,
      ) {
        if (mounted) widget.onFinished?.call();
      }),
    );
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
    _motion?._dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final motion = _motion!;
    return _LaunchEntranceScope(
      motion: motion,
      child: SnapshotSweep(controller: motion.screen, child: widget.child),
    );
  }
}

class _LaunchEntranceScope extends InheritedWidget {
  const _LaunchEntranceScope({required this.motion, required super.child});

  final LaunchEntranceMotion motion;

  @override
  bool updateShouldNotify(_LaunchEntranceScope oldWidget) =>
      !identical(motion, oldWidget.motion);
}

/// 開 App 進場時，頁首與分頁列的一個元件先畫成骨架，和書架的骨架一起
/// 出現、一起呼吸；書架換場時整個畫面一起換成真的（[LaunchEntrance]）。
/// 骨架出現由左而右時照元件中心的橫向位置決定先後，和書架的掃動對齊。
///
/// - 玻璃（頁首按鈕、分頁列、搜尋鈕）：骨架照它的大小與 [borderRadius] 畫
///   （圓鈕就是最窄的膠囊）。
/// - 一行字（[LaunchSkeleton.text]，頁首標題）：骨架是和字同寬、和字一樣高
///   的長條（同 [SkeletonLine]）。
///
/// 換成真的之前 [child] 不畫（玻璃不取樣背景）、不接點擊、不給讀屏念，但
/// 一直在元件樹裡，按鈕的狀態不丟。不在進場底下，或進場結束後才建的（例如
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

  LaunchEntranceMotion? _motion;

  /// 建立時進場已經換成真的（或不在進場底下）：一直直接畫。
  bool _passThrough = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final motion = LaunchEntrance.maybeOf(context);
    if (_motion == null) {
      _motion = motion;
      _passThrough = motion == null || motion.revealed.value;
    }
    if (_passThrough || _motion!.revealed.value) return;
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
    // 字的骨架是一條和字一樣高的長條，置中在那一行上。
    final barHeight = style == null
        ? null
        : MediaQuery.textScalerOf(context).scale(style.fontSize ?? 14) *
              Skeleton.barHeightFactor;
    return ValueListenableBuilder<bool>(
      valueListenable: motion.revealed,
      child: widget.child,
      builder: (context, revealed, child) {
        final hidden = !revealed;
        // 元件樹一直相同，換成真的時按鈕的狀態不丟。
        return Stack(
          fit: StackFit.passthrough,
          children: [
            _PaintedWhen(
              shown: revealed,
              child: IgnorePointer(
                ignoring: hidden,
                child: ExcludeSemantics(excluding: hidden, child: child),
              ),
            ),
            if (hidden)
              Positioned.fill(
                child: IgnorePointer(
                  child: Center(
                    child: AnimatedBuilder(
                      animation: motion.skeleton,
                      builder: (context, _) {
                        final appeared = SkeletonReveal.incomingOpacityAt(
                          motion.skeleton.value,
                          _u,
                          sweep: motion.sweep,
                        );
                        final base = Skeleton.colorOf(context);
                        return Skeleton(
                          child: SkeletonBox(
                            width: double.infinity,
                            height: barHeight ?? double.infinity,
                            borderRadius: widget.borderRadius,
                            color: base.withValues(alpha: base.a * appeared),
                          ),
                        );
                      },
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

/// [shown] 為 false 時排版照常、不畫：玻璃不取樣背景，也不另開圖層。
class _PaintedWhen extends SingleChildRenderObjectWidget {
  const _PaintedWhen({required this.shown, required super.child});

  final bool shown;

  @override
  _RenderPaintedWhen createRenderObject(BuildContext context) =>
      _RenderPaintedWhen(shown);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderPaintedWhen renderObject,
  ) {
    renderObject.shown = shown;
  }
}

class _RenderPaintedWhen extends RenderProxyBox {
  _RenderPaintedWhen(this._shown);

  bool _shown;
  set shown(bool value) {
    if (_shown == value) return;
    _shown = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_shown) super.paint(context, offset);
  }
}
