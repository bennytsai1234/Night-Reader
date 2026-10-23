import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/app_tokens.dart';
import 'painted_when.dart';
import 'skeleton.dart';
import 'skeleton_reveal.dart';
import 'snapshot_sweep.dart';

/// 開 App 的進場（ADR 0025）：系統啟動畫面只有底色，Flutter 第一幀也只畫
/// 底色；接著整個畫面照骨架換場（[SkeletonReveal]）的方式與時長長出骨架：
/// 書架、頁首的標題與兩側按鈕、底部分頁列（書架以外用 [LaunchSkeleton]）。
/// 骨架呼吸著等書架準備好（書、封面、書名的繁簡轉換），書架換場時整個畫面
/// 一起換成真的：呼吸先收住、停在最深，在靜止的畫面上把骨架畫面與換好的
/// 畫面各畫成一張圖，換場的 0.6 秒
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

  /// 骨架長完之後至少停多久才換成內容：一個骨架呼吸（由深到淺一次，
  /// [AppMotion.skeletonPulse]）。準備得比這久就等到準備好；使用者在候選
  /// 動圖上選的（2026-10-23）：不固定的停頓短時，兩次由左而右的掃動像同一個
  /// 動作中途頓住。
  static const Duration pause = AppMotion.skeletonPulse;

  /// 換場前收住骨架的呼吸（[reveal]）：拍定格畫面的那幾格畫面一定停住，
  /// 呼吸到一半定住就是頓一下（使用者 2026-10-23 在手機上看到的）；先讓
  /// 每個位置把這一口氣呼完、停在最深，再在靜止的畫面上拍。
  final SkeletonRest rest = SkeletonRest();

  /// 呼吸停好後畫面至少靜止多久才開始換場；拍圖的那幾格（電腦上兩格合計
  /// 約 180ms）落在這段裡，拍得比這久就拍完才換。取使用者提的 100–200ms
  /// 的中間：太短時停住接著就掃，像同一個動作頓了一下。
  static const Duration hold = Duration(milliseconds: 150);

  /// 骨架長完、停過 [pause] 時完成；系統要求減少動態時不停。
  Future<void> get _paused => _pauseOver.future;
  final Completer<void> _pauseOver = Completer<void>();

  /// 整段進場結束時完成。
  Future<void> get finished => _finished.future;
  final Completer<void> _finished = Completer<void>();

  /// 書架第一次換成內容：骨架長完停過 [pause]、呼吸收住（[rest]）後，
  /// [change] 把書架換成內容，頁首按鈕、標題與分頁列同時換成真的，整個畫面
  /// 靜止至少 [hold] 再照 [screen] 換場（[sweep] 時由左而右）；播完才算整段
  /// 進場結束。之後再呼叫（書架重新載入）只做 [change]。
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
    await _paused;
    await rest.settle();
    await screen.play(
      duration: duration,
      sweep: sweep,
      hold: hold,
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
    rest.release();
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
      motion._pauseOver.complete();
      return;
    }
    // 骨架長完才開始算停頓；停頓用計時器，不靠哪一格畫完。
    void onStatus(AnimationStatus status) {
      if (!status.isCompleted) return;
      _controller.removeStatusListener(onStatus);
      _pause = Timer(LaunchEntranceMotion.pause, () {
        if (!motion._pauseOver.isCompleted) motion._pauseOver.complete();
      });
    }

    _controller.addStatusListener(onStatus);
    // 第一幀只畫底色、和系統啟動畫面一樣，畫完才開始進場。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.forward();
    });
  }

  Timer? _pause;

  @override
  void dispose() {
    _pause?.cancel();
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
            PaintedWhen(
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
