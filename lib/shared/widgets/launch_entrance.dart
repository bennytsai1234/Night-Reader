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
/// 底色；開 App 的準備工作（[prepared]）做完、畫面畫完，先清掉開 App 留下
/// 的記憶體（[_collectStartupGarbage]），再隔 [LaunchEntranceMotion.idle]，
/// 整個畫面才照骨架換場（[SkeletonReveal]）的方式與時長長出骨架：書架、頁首
/// 的標題與兩側按鈕、底部分頁列（書架以外用 [LaunchSkeleton]）。長出時骨架
/// 不呼吸、長到最深，長完再停 [LaunchEntranceMotion.idle] 才由左而右呼吸一口
/// （[Skeleton] 底下的呼吸看這裡的 [LaunchEntranceMotion.breathing]）；呼吸
/// 時底下不做事。呼完收住、停在最深，在靜止的畫面上一次準備好書架與封面，
/// 把骨架畫面與換好的畫面各畫成一張圖，拍好再隔 [LaunchEntranceMotion.idle]
/// 才換場：換場的 0.6 秒只把兩張圖照每個像素的橫向位置混合
/// （[SnapshotSweep]，ADR 0031），頁首、分頁列與書架照同一條曲線由左而右
/// 換過去。動畫在動的每一格，主執行緒都不做別的事。
///
/// 包在主頁面外面；底下的頁首（`GlassNavHeader`）、分頁列與書架用
/// [maybeOf] 取得進場的狀態。從主頁面推出去的頁面不在底下，不受影響。
/// 系統要求減少動態時骨架直接到位、換場直接換好。
class LaunchEntrance extends StatefulWidget {
  const LaunchEntrance({
    super.key,
    required this.child,
    this.onFinished,
    this.prepared,
  });

  final Widget child;

  /// 整段進場結束時呼叫一次：開 App 的背景工作從這裡才開始，不和進場搶
  /// 主執行緒（ADR 0018）。
  final VoidCallback? onFinished;

  /// 開 App 的準備工作（讀書架、載入繁簡字典）做完時完成；第一幀畫完後
  /// 呼叫。資料回來會讓畫面重建一次，等它做完才開始長骨架，這次重建不會
  /// 落在長出的第一格。null 時第一幀畫完就開始。
  final Future<void> Function()? prepared;

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

  /// 開 App 的骨架呼吸由深到淺一次的時間；一口氣是它的兩倍（0.6 秒）。和
  /// 長出對稱：長出時每個位置花 0.3 秒長好、右邊晚 0.3 秒，呼吸也是每個
  /// 位置 0.3 秒變淺、右邊晚 0.3 秒（由左而右・緩的延遲是半輪）。使用者
  /// 2026-10-24 定的；閱讀器紙上與重新載入時的骨架照舊用
  /// [AppMotion.skeletonPulse]。
  static const Duration breath = Duration(milliseconds: 300);

  /// 開 App 的骨架呼吸一輪的時長。
  static Duration get breathCycle => breath * 2;

  /// 開始呼吸後多久開始收住：呼吸半輪，收住時每個位置再把這一口氣呼完，
  /// 每個位置剛好呼一口（使用者 2026-10-23 選「固定停一口氣」）。
  static const Duration pause = breath;

  /// 主執行緒的一段工作做完後，隔多久才播下一段動畫：開 App 的準備工作
  /// 之後才長骨架、長完的重建之後才呼吸、拍完兩張定格畫面之後才換場。
  /// 動畫的每一格都不和工作擠在一起，手機慢的時候工作拖長，間隔照樣在
  /// （使用者 2026-10-24 定的，原本是從開始拍起至少停 0.15 秒）。
  static const Duration idle = Duration(milliseconds: 100);

  /// 換場前收住骨架的呼吸（[reveal]）：拍定格畫面的那幾格畫面一定停住，
  /// 呼吸到一半定住就是頓一下（使用者 2026-10-23 在手機上看到的）；先讓
  /// 每個位置把這一口氣呼完、停在最深，再在靜止的畫面上拍。
  final SkeletonRest rest = SkeletonRest();

  /// 骨架長完、停過 [idle] 後開始呼吸（[Skeleton] 聽它）；一旦開始就一直是
  /// true。長完那一格要把骨架從長出換成呼吸、整片重建一次，停一下讓這次
  /// 重建落在靜止的畫面上，呼吸的第一格才不會跟著重。
  ValueListenable<bool> get breathing => _breathing;
  final ValueNotifier<bool> _breathing = ValueNotifier(false);

  /// 整段進場已經結束：之後才建的骨架照一般的節奏呼吸。
  bool get isFinished => _finished.isCompleted;

  /// 開始呼吸、停過 [pause] 時完成；系統要求減少動態時不停。
  Future<void> get _paused => _pauseOver.future;
  final Completer<void> _pauseOver = Completer<void>();

  /// 整段進場結束時完成。
  Future<void> get finished => _finished.future;
  final Completer<void> _finished = Completer<void>();

  /// 書架第一次換成內容：呼吸停過 [pause]、收住（[rest]）後，[change] 把
  /// 書架換成內容，頁首按鈕、標題與分頁列同時換成真的，兩張定格畫面拍好
  /// 再隔 [idle] 照 [screen] 換場（[sweep] 時由左而右）；播完才算整段進場
  /// 結束。之後再呼叫（書架重新載入）只做 [change]。
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
    await settleBreath();
    // 等的期間整個進場被拆掉了（例如 App 換掉主頁面）：不再換場。
    if (_disposed) return;
    await screen.play(
      duration: duration,
      sweep: sweep,
      gap: idle,
      change: () {
        change();
        if (!_disposed) _revealed.value = true;
      },
    );
    if (!_disposed) _finish();
  }

  /// 停頓滿了、呼吸也收住（[rest]），畫面靜止時完成。開 App 的書架等它才在
  /// 骨架底下準備內容：準備的工作全落在靜止的畫面裡，呼吸的每一格底下都
  /// 不做事（ADR 0031）。重複呼叫回傳同一個。
  Future<void> settleBreath() => _breathSettling ??= _settleBreath();
  Future<void>? _breathSettling;

  /// [settleBreath] 已經完成。
  bool get breathSettled => _breathSettled;
  bool _breathSettled = false;

  Future<void> _settleBreath() async {
    await _paused;
    await rest.settle();
    // 最後一個位置是在某一格的動畫階段停好的，那一格還沒畫：等它畫完、畫面
    // 真的靜止了，下一格才開始準備書架。不然建書架會擠進收住的最後一格。
    await SchedulerBinding.instance.endOfFrame;
    _breathSettled = true;
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

  bool _disposed = false;

  void _dispose() {
    _disposed = true;
    _revealed.dispose();
    _breathing.dispose();
  }
}

/// 開 App 留下的記憶體先清掉：故意產生一批用完即丟的小物件，讓 Dart 的
/// 記憶體回收在還沒開始動畫時跑幾次。開 App 建好的畫面與讀進來的資料都還
/// 在新生區，第一次回收要把它們整批搬走，最貴；不先清，這次回收會落在
/// 呼吸開始後約 0.18 秒（呼吸每格重畫骨架會產生物件，新生區很快就滿），
/// 一格多花十幾毫秒（2026-10-24 量到）。Dart 沒有「現在回收」的 API。
///
/// 每塞約 1MB 看一次探針：一個沒人引用的物件被清掉，就是剛回收過一次；
/// 回收 [collections] 次就停，不照固定的大小塞，換手機（新生區大小不同）
/// 也剛好清夠。小實驗：回收 2 次（約 17MB）時呼吸還剩一格 7～10ms，
/// 4 次（約 50MB，電腦 debug 約 40ms）時呼吸每格都在 5ms 內。[maxBytes]
/// 只是保險，正常不會到。
void _collectStartupGarbage({int collections = 4, int maxBytes = 256 << 20}) {
  const perCheck = 16 * 1024; // 每個 4 格的 List 約 64 位元組，一次約 1MB
  final ring = List<Object?>.filled(1024, null);
  var probe = WeakReference(Object());
  var seen = 0;
  for (var bytes = 0; seen < collections && bytes < maxBytes;) {
    for (var i = 0; i < perCheck; i++) {
      ring[i & 1023] = List<int>.filled(4, i);
    }
    bytes += perCheck * 64;
    if (probe.target == null) {
      seen++;
      probe = WeakReference(Object());
    }
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
      motion._breathing.value = true;
      motion._pauseOver.complete();
      return;
    }
    // 骨架長完，這一格整片重建；停 idle 才開始呼吸，開始呼吸才算停頓。
    // 都用計時器，不靠哪一格畫完。
    void onStatus(AnimationStatus status) {
      if (!status.isCompleted) return;
      _controller.removeStatusListener(onStatus);
      _timer = Timer(LaunchEntranceMotion.idle, () {
        motion._breathing.value = true;
        _timer = Timer(LaunchEntranceMotion.pause, () {
          if (!motion._pauseOver.isCompleted) motion._pauseOver.complete();
        });
      });
    }

    _controller.addStatusListener(onStatus);
    // 第一幀只畫底色、和系統啟動畫面一樣；畫完、準備工作也做完，清掉開 App
    // 留下的記憶體，再隔 idle 才開始長骨架。
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await widget.prepared?.call();
      // 資料回來排的那次重建：等它畫完。
      await SchedulerBinding.instance.endOfFrame;
      if (!mounted) return;
      _collectStartupGarbage();
      _timer = Timer(LaunchEntranceMotion.idle, () {
        if (mounted) _controller.forward();
      });
    });
  }

  /// 長骨架前的間隔、長完到呼吸的間隔與停頓，同一時間只有一個。
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
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
