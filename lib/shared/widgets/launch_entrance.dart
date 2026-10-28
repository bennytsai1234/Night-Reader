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
/// 的記憶體（[_collectGarbage]），再隔 [LaunchEntranceMotion.idle]，
/// 整個畫面才照骨架換場（[SkeletonReveal]）的方式與時長長出骨架：書架、頁首
/// 的標題與兩側按鈕、底部分頁列（書架以外用 [LaunchSkeleton]）。長出時骨架
/// 不呼吸、長到最深；長完、書也讀到了，就在靜止的畫面上一次準備好書架與
/// 封面，把骨架畫面與換好的畫面各畫成一張圖、換回骨架，清掉建書架留下的
/// 記憶體，再停 [LaunchEntranceMotion.idle] 才由左而右呼吸一口（[Skeleton]
/// 底下的呼吸看這裡的 [LaunchEntranceMotion.breathing]，ADR 0035）；呼吸時
/// 底下不做事。呼完收住、停在最深就換場：換場的 0.6 秒只把兩張圖照每個像素
/// 的橫向位置混合（[SnapshotSweep]，ADR 0031），頁首、分頁列與書架照同一條
/// 曲線由左而右換過去。長完時書還沒讀到，呼吸收住後才準備、拍圖，再隔
/// [LaunchEntranceMotion.idle] 換場。動畫在動的每一格，主執行緒都不做別的事。
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

  /// 頁首按鈕、標題與分頁列已經換成真的（[LaunchSkeleton] 聽它）。換場時換
  /// 成 true 就一直是 true，之後書架重新載入不再影響它們；呼吸前拍定格畫面
  /// 時（[capture]）暫時換成真的、拍好換回來。
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

  /// 長完那一格畫完時決定要不要先準備書架；之後才到的書架照呼吸收住後準備。
  bool _breathScheduled = false;

  /// 書架要在呼吸前準備（[requestPreparation]）：長完那一格畫完時完成。
  Completer<void>? _preparationStart;

  /// 呼吸前的準備做完（或放棄）時完成，之後才開始呼吸。
  final Completer<void> _preparationDone = Completer<void>();

  /// 骨架長完時書架的資料已經到了：長完那一格畫完就在靜止的畫面上建好書架、
  /// 等封面、拍好兩張定格畫面（[capture]），清掉記憶體再隔 [idle] 才開始
  /// 呼吸，呼吸收住就直接換場；呼吸的每一格與換場前都不再做重的工作
  /// （ADR 0035）。回傳開始準備的時刻；太晚（已經排好呼吸）時回傳 null，
  /// 照呼吸收住後再準備（[settleBreath]）。重複呼叫回傳同一個。
  Future<void>? requestPreparation() {
    if (_breathScheduled) return null;
    return (_preparationStart ??= Completer<void>()).future;
  }

  /// 正在做呼吸前的準備（[requestPreparation]）。
  bool get preparing =>
      (_preparationStart?.isCompleted ?? false) &&
      !_preparationDone.isCompleted;

  /// 呼吸前的準備做完或放棄（例如書架又回到載入中）：開始呼吸。
  void donePreparing() {
    if (!_preparationDone.isCompleted) _preparationDone.complete();
  }

  /// 呼吸前拍好兩張定格畫面：[change] 把書架換成內容，頁首按鈕、標題與
  /// 分頁列同時換成真的，拍下後 [restore] 換回骨架（[SnapshotSweepController.capture]）；
  /// 做完準備（[donePreparing]）。
  Future<void> capture({
    required VoidCallback change,
    required VoidCallback restore,
  }) async {
    var shown = false;
    try {
      await screen.capture(
        change: () {
          change();
          shown = true;
          if (!_disposed) _revealed.value = true;
        },
        restore: () {
          restore();
          shown = false;
          if (!_disposed) _revealed.value = false;
        },
      );
    } finally {
      // 拍到一半就放棄（書架又回到載入中、被拆掉）：頁首與分頁列換回骨架。
      if (shown && !_disposed) _revealed.value = false;
      donePreparing();
    }
  }

  /// 書架第一次換成內容：呼吸停過 [pause]、收住（[rest]）後，[change] 把
  /// 書架換成內容，頁首按鈕、標題與分頁列同時換成真的，照 [screen] 換場
  /// （[sweep] 時由左而右）；播完才算整段進場結束。兩張定格畫面呼吸前已經
  /// 拍好（[capture]）時，換上「之前」那張圖的下一格就開始換場；還沒拍時
  /// 這時才拍，拍好、清掉記憶體再隔 [idle] 才換場。之後再呼叫（書架重新
  /// 載入）只做 [change]。
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
    final captured = screen.captured;
    await screen.play(
      duration: duration,
      sweep: sweep,
      gap: captured ? Duration.zero : idle,
      // 換場前畫面停著時清掉建書架留下的記憶體：不清的話，換場開始後約
      // 0.15 秒 Dart 趁兩格之間的空檔回收一次，手機上一次 12～13ms，超過
      // 一格（120Hz 是 8.3ms），換場途中掉一格（2026-10-25 量到）。呼吸前
      // 拍好的已經在呼吸前清過。
      settle: captured ? null : _collectGarbage,
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
    donePreparing();
    _revealed.dispose();
    _breathing.dispose();
  }
}

/// 趁畫面靜止時清掉記憶體，不讓回收落在接下來的動畫裡：長骨架前清開 App
/// 留下的，書架換場前清建書架留下的（[SnapshotSweepController.play] 的
/// settle）。故意產生一批用完即丟的小物件，讓 Dart 的
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
///
/// 新生區回收幾次後，還在用的東西都搬進了舊生區，舊生區變大，Dart 隨即
/// 開始回收舊生區；只清新生區的話，這次回收的停頓落在接下來的動畫裡：
/// 骨架長出約第 30 幀、呼吸開始後幾幀，電腦上一次 5～14ms，改前四次量測
/// 每次都有（2026-10-28）。所以接著也把舊生區清一次：一個物件先留著，
/// 跟著新生區回收搬進舊生區後放手，再一次塞 1MB（大塊直接配在舊生區），
/// 直到它被清掉，就是舊生區回收完一次；電腦 debug 塞約 55～80MB、20ms。
/// 清完舊生區也小了，動畫途中 Dart 不會趁兩格之間的空檔再開始回收它。
/// [maxOldBytes] 只是保險。
///
/// 探針的建立、兩段塞垃圾與檢查各自是一個不併進呼叫端的函式：全寫在同一
/// 個函式裡時，探針在 App 裡一直清不掉（還被這個函式的暫存留著），每次都
/// 塞滿 128MB，塞出來的垃圾反而讓 Dart 在動畫途中回收舊生區，一次 5～11ms
/// （2026-10-28 量到）。
void _collectGarbage({
  int collections = 4,
  int maxBytes = 256 << 20,
  int maxOldBytes = 128 << 20,
}) {
  final aging = List<Object?>.filled(1, null);
  final old = _holdProbe(aging);
  _churnNew(collections, maxBytes);
  aging[0] = null;
  _churnOld(old, maxOldBytes);
}

/// 塞小物件到新生區回收 [collections] 次（[_collectGarbage]）。
@pragma('vm:never-inline')
void _churnNew(int collections, int maxBytes) {
  const perCheck = 16 * 1024; // 每個 4 格的 List 約 64 位元組，一次約 1MB
  final ring = List<Object?>.filled(1024, null);
  var probe = WeakReference(Object());
  var seen = 0;
  var bytes = 0;
  while (seen < collections && bytes < maxBytes) {
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

/// 塞大塊到舊生區，直到 [old] 被清掉（[_collectGarbage]）。
@pragma('vm:never-inline')
void _churnOld(WeakReference<Object> old, int maxBytes) {
  const chunk = 1 << 20;
  final ring = List<Object?>.filled(1, null);
  var bytes = 0;
  while (!_isGone(old) && bytes < maxBytes) {
    // 只留最後一塊，前一塊就成了舊生區的垃圾。
    ring[0] = Uint8List(chunk);
    bytes += chunk;
  }
}

/// 建一個只由 [holder] 留著的探針，回傳它的弱參照。
@pragma('vm:never-inline')
WeakReference<Object> _holdProbe(List<Object?> holder) {
  final probe = Object();
  holder[0] = probe;
  return WeakReference(probe);
}

@pragma('vm:never-inline')
bool _isGone(WeakReference<Object> probe) => probe.target == null;

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
      // 沒有長出與呼吸，也就沒有呼吸前的準備：書架到了直接換成內容。
      motion._breathScheduled = true;
      motion._breathing.value = true;
      motion._pauseOver.complete();
      return;
    }
    // 骨架長完，這一格整片重建：等它畫完，書架的資料已經到了就先準備書架、
    // 拍好兩張定格畫面（[LaunchEntranceMotion.requestPreparation]），清掉
    // 留下的記憶體，再停 idle 才開始呼吸（長完的通知在這一格建畫面之前，從
    // 那時就算的話，這一格越重、停得越短），開始呼吸才算停頓。
    void onStatus(AnimationStatus status) {
      if (!status.isCompleted) return;
      _controller.removeStatusListener(onStatus);
      SchedulerBinding.instance.endOfFrame.then((_) async {
        if (!mounted) return;
        motion._breathScheduled = true;
        final start = motion._preparationStart;
        if (start != null) {
          start.complete();
          await motion._preparationDone.future;
          if (!mounted) return;
          _collectGarbage();
        }
        _timer = Timer(LaunchEntranceMotion.idle, () {
          motion._breathing.value = true;
          _timer = Timer(LaunchEntranceMotion.pause, () {
            if (!motion._pauseOver.isCompleted) motion._pauseOver.complete();
          });
        });
      });
    }

    _controller.addStatusListener(onStatus);
    // 第一幀只畫底色、和系統啟動畫面一樣；畫完、準備工作也做完，清掉開 App
    // 留下的記憶體，再隔 idle 才開始長骨架。
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await widget.prepared?.call();
      } catch (error, stackTrace) {
        // 準備工作失敗也照常進場：書架自己會顯示讀不到，不能停在底色。
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'launch entrance',
            context: ErrorDescription('開 App 的準備工作失敗'),
          ),
        );
      }
      // 資料回來排的那次重建：等它畫完。
      await SchedulerBinding.instance.endOfFrame;
      if (!mounted) return;
      _collectGarbage();
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
