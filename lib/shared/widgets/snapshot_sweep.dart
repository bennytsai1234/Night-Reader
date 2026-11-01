import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'skeleton_reveal.dart';

/// 兩張定格畫面之間的骨架換場（ADR 0029）：換場開始前把現在的畫面（之前）
/// 與換好的畫面（之後）各畫成一張圖，換場的每一格只照每一行像素的橫向位置
/// 與 [SkeletonReveal.incomingOpacityAt] 的曲線把兩張圖混在一起，播完才換回
/// 真的畫面。
///
/// 換場那幾格手機只要貼兩張圖：玻璃的背景模糊、陰影、封面與文字都已經在
/// 「之後」那張圖裡畫好一次，不必每一格重新合成；畫面上每個像素都照同一條
/// 曲線從之前換到之後，頁首按鈕、標題與分頁列不會各有各的時機。代價是換場
/// 前多畫一格（畫出換好的樣子、拍下來，這一格螢幕上蓋著「之前」那張圖，
/// 看起來不動），換場期間多佔兩張螢幕大小的圖，也不接點擊與捲動。換場的
/// 0.6 秒裡底下又有變化（網路封面到了、換深淺色）時照舊播完，播完才一次
/// 換到最新的樣子；畫面大小變了（旋轉、視窗縮放）時兩張圖對不上，直接
/// 結束換場、換回真的畫面。
///
/// 包在要換場的範圍外面（例如整個主頁面）；要換場的地方用 [controller] 的
/// [SnapshotSweepController.play]，可以先 [SnapshotSweepController.capture]
/// 趁畫面靜止時拍好兩張圖、畫面照常，之後才播（ADR 0035）。
class SnapshotSweep extends StatefulWidget {
  const SnapshotSweep({
    super.key,
    required this.controller,
    required this.child,
  });

  final SnapshotSweepController controller;
  final Widget child;

  @override
  State<SnapshotSweep> createState() => _SnapshotSweepState();
}

/// 交給 [SnapshotSweep] 播一次換場。
class SnapshotSweepController {
  _SnapshotSweepState? _state;

  /// 先拍好兩張圖、畫面照常（開 App 時骨架接著呼吸），之後才 [play]：拍下
  /// 現在的畫面，呼叫 [change] 把底下換成換好的樣子，畫好後拍下來，再呼叫
  /// [restore] 換回原本的樣子；換回的那一格畫完時完成。拍圖這幾格螢幕上蓋著
  /// 「之前」那張圖，看起來不動；換回後的畫面要和「之前」一樣。
  ///
  /// 拍好到 [play] 之間底下又變了（網路封面到了、換深淺色）時照舊用拍好的
  /// 圖，播完才一次換到最新的樣子。不在 [SnapshotSweep] 底下或系統要求減少
  /// 動態時不拍，[play] 照常處理。
  Future<void> capture({
    required VoidCallback change,
    required VoidCallback restore,
  }) {
    final state = _state;
    if (state == null || !state.mounted) return Future<void>.value();
    return state._capture(change, restore);
  }

  /// 花 [duration] 把「之前」換成「之後」：[sweep] 時由左而右（同
  /// [SkeletonReveal.incomingOpacityAt]），否則整片淡換。換場播完、換回真的
  /// 畫面時完成。
  ///
  /// 已經 [capture] 好時，[change] 與螢幕換上「之前」那張圖在同一格；還沒拍
  /// 時先拍下現在的畫面、[change]、畫好後拍下換好的。之後停住的畫面畫完，
  /// 先做 [settle]（給呼叫端趁畫面靜止時做的事），再停 [gap] 才開始換場：
  /// 拍圖是這段最重的主執行緒工作，手機拍得再慢，換場也不會緊接在拍完的
  /// 那一格開始（ADR 0025）。
  ///
  /// 不在 [SnapshotSweep] 底下，或系統要求減少動態時，直接 [change]。
  Future<void> play({
    required VoidCallback change,
    required Duration duration,
    bool sweep = true,
    Duration gap = Duration.zero,
    VoidCallback? settle,
  }) {
    final state = _state;
    if (state == null || !state.mounted) {
      change();
      return Future<void>.value();
    }
    return state._play(change, duration, sweep, gap, settle);
  }

  /// 開 App 長骨架前拍好兩張圖（ADR 0035 的延伸）：「只有底色」是現在的
  /// 畫面，呼叫 [change] 把骨架整個長出來（最深），畫好後拍下「骨架最深」，
  /// 再呼叫 [restore] 換回底色；換回的那一格畫完時完成，拍到時回傳 true。
  /// 拍圖這幾格螢幕上蓋著「只有底色」那張圖，看起來不動。
  ///
  /// 拍好後骨架長出與呼吸都只混合這兩張圖（[mixSkeleton]），不重畫骨架。
  /// 不在 [SnapshotSweep] 底下、系統要求減少動態或還沒畫出來時不拍，回傳
  /// false，骨架照常即時畫。
  Future<bool> captureSkeleton({
    required VoidCallback change,
    required VoidCallback restore,
  }) {
    final state = _state;
    if (state == null || !state.mounted) return Future<bool>.value(false);
    return state._captureSkeleton(change, restore);
  }

  /// 螢幕上改畫「只有底色」與「骨架」兩張圖照每一行像素混合：橫向位置 u
  /// （0 左緣、1 右緣）那一行是 底色 +（骨架 − 底色）×[depthAt] (u)。骨架的
  /// 顏色是半透明疊上去的，所以和把每個骨架形狀的透明度乘上 [depthAt] 畫
  /// 出來一樣。[tick] 每次通知就重畫一次；底下的畫面不畫。
  ///
  /// 「骨架」先用 [captureSkeleton] 拍的那張；換場的兩張圖拍好（[capture]）
  /// 之後改用「之前」那張（同樣是骨架最深的畫面），先拍的那張放掉。沒有
  /// 圖、圖和畫面大小對不上，或換場開始時（[play]），換回真的畫面。
  void mixSkeleton(Listenable tick, double Function(double u) depthAt) =>
      _state?._mixSkeleton(tick, depthAt);

  /// 停止 [mixSkeleton]，換回真的畫面（圖留著，之後還可以再混合）。
  void stopMixingSkeleton() => _state?._stopMixing();

  /// 放掉 [captureSkeleton] 拍的圖，停止混合。
  void releaseSkeleton() => _state?._releaseSkeleton();

  /// 兩張圖已經 [capture] 好、還沒開始 [play]。
  bool get captured => _state?._phase == _Phase.captured;

  /// 螢幕上只貼兩張圖、底下不畫：換場中，或拍好後開始掃之前停住的那幾格。
  bool get playing => _state?._phase == _Phase.playing;

  /// 拍到一半、拍好還沒播，或換場還沒播完時，換回真的畫面（底下已經換好）、
  /// 放掉圖，完成這一次換場。建畫面途中呼叫時（例如底下的元件在
  /// didUpdateWidget 裡）等這一幀畫完再換。
  void finish() {
    final state = _state;
    final session = state?._session;
    if (state == null || session == null) return;
    final scheduler = SchedulerBinding.instance;
    if (scheduler.schedulerPhase != SchedulerPhase.persistentCallbacks) {
      state._end();
      return;
    }
    scheduler.addPostFrameCallback((_) {
      if (state.mounted && identical(state._session, session)) state._end();
    });
  }
}

enum _Phase {
  /// 畫真的畫面。
  live,

  /// 已經拍好「之前」、底下換成了換好的樣子：螢幕上蓋著「之前」那張圖，
  /// 等底下畫好拍「之後」。
  holding,

  /// 兩張圖都拍好、底下換回原本的樣子（[SnapshotSweepController.capture]），
  /// 畫真的畫面，等 [SnapshotSweepController.play]。
  captured,

  /// 兩張圖混合中，底下不畫。
  playing,
}

class _SnapshotSweepState extends State<SnapshotSweep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress = AnimationController(vsync: this);
  final GlobalKey _boundaryKey = GlobalKey();

  _Phase _phase = _Phase.live;
  ui.Image? _before;
  ui.Image? _after;
  bool _sweep = true;

  /// 這一輪（拍圖到換場播完）；結束或被下一輪蓋過時換掉。
  Object? _session;

  /// [SnapshotSweepController.capture] 拍好、換回原本的樣子時完成。
  Completer<void>? _captured;

  /// [SnapshotSweepController.play] 換場播完時完成。
  Completer<void>? _run;

  /// [SnapshotSweepController.captureSkeleton] 拍的「只有底色」與「骨架最深」；
  /// [_cover] 是拍骨架那幾格蓋在螢幕上的圖（就是 [_base]）。
  ui.Image? _base;
  ui.Image? _skeleton;
  ui.Image? _cover;

  /// 這一輪拍骨架；放掉或被下一輪蓋過時換掉。
  Object? _skeletonSession;

  /// [SnapshotSweepController.mixSkeleton] 正在混合時的重畫時機與每個橫向
  /// 位置的深淺。
  Listenable? _mixTick;
  double Function(double u)? _mixDepth;

  @override
  void initState() {
    super.initState();
    widget.controller._state = this;
  }

  @override
  void didUpdateWidget(SnapshotSweep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.controller, widget.controller)) return;
    if (identical(oldWidget.controller._state, this)) {
      oldWidget.controller._state = null;
    }
    widget.controller._state = this;
  }

  @override
  void dispose() {
    if (identical(widget.controller._state, this)) {
      widget.controller._state = null;
    }
    _end(rebuild: false);
    _releaseSkeleton(rebuild: false);
    _progress.dispose();
    super.dispose();
  }

  Future<bool> _captureSkeleton(
    VoidCallback change,
    VoidCallback restore,
  ) async {
    _releaseSkeleton();
    if (MediaQuery.disableAnimationsOf(context)) return false;
    final session = _skeletonSession = Object();
    bool current() => mounted && identical(_skeletonSession, session);

    /// 下一格畫完、拍得到（沒有要重畫）時拍下底下的畫面；拍不到時回傳 null。
    Future<ui.Image?> shoot() async {
      while (true) {
        await _nextFrame();
        if (!current()) return null;
        final boundary = _boundary;
        if (boundary == null) return null;
        if (!_readyToCapture(boundary)) continue;
        final image = await _toImage(boundary);
        if (current()) return image;
        image.dispose();
        return null;
      }
    }

    final base = await shoot();
    if (base == null) return false;
    // 底下長出骨架；這一格（與拍骨架之前的每一格）螢幕上蓋著只有底色的圖。
    change();
    setState(() => _base = _cover = base);
    ui.Image? skeleton;
    try {
      skeleton = await shoot();
    } finally {
      restore();
      if (current()) setState(() => _cover = null);
    }
    if (skeleton == null) {
      if (current()) _releaseSkeleton();
      return false;
    }
    _skeleton = skeleton;
    // 換回底色的那一格畫完才算拍好。
    await _nextFrame();
    return current();
  }

  /// 下一格畫完時完成。
  Future<void> _nextFrame() {
    final done = Completer<void>();
    _afterFrame(done.complete);
    return done.future;
  }

  void _mixSkeleton(Listenable tick, double Function(double u) depthAt) {
    if (!mounted || _base == null) return;
    setState(() {
      _mixTick = tick;
      _mixDepth = depthAt;
    });
  }

  void _stopMixing() {
    if (!mounted || _mixTick == null) return;
    setState(() {
      _mixTick = null;
      _mixDepth = null;
    });
  }

  void _releaseSkeleton({bool rebuild = true}) {
    final base = _base, skeleton = _skeleton;
    _skeletonSession = null;
    void reset() {
      _base = _skeleton = _cover = null;
      _mixTick = null;
      _mixDepth = null;
    }

    if (rebuild && mounted && (base != null || skeleton != null)) {
      setState(reset);
    } else {
      reset();
    }
    base?.dispose();
    skeleton?.dispose();
  }

  RenderRepaintBoundary? get _boundary {
    final object = _boundaryKey.currentContext?.findRenderObject();
    return object is RenderRepaintBoundary && object.hasSize ? object : null;
  }

  /// 這一格畫完後它的圖層就是螢幕上的樣子，可以拍；除錯模式下若有人在
  /// 這之後又要求重畫，等下一格（正式版拍的仍是螢幕上那一格）。
  bool _readyToCapture(RenderRepaintBoundary boundary) {
    var dirty = false;
    assert(() {
      dirty = boundary.debugNeedsPaint;
      return true;
    }());
    return !dirty;
  }

  /// 兩張都拍好後要再停多久（[SnapshotSweepController.play] 的 gap）。
  Duration _gap = Duration.zero;

  /// 兩張都拍好、停住的畫面畫完後做的事（[SnapshotSweepController.play] 的
  /// settle）。
  VoidCallback? _settle;

  /// 拍好後停的計時器；結束才開始換場。
  Timer? _hold;

  bool _current(Object session) => mounted && identical(_session, session);

  Future<void> _capture(VoidCallback change, VoidCallback restore) {
    _end();
    if (MediaQuery.disableAnimationsOf(context)) return Future<void>.value();
    final session = _session = Object();
    final captured = _captured = Completer<void>();
    _afterFrame(
      () => _captureBefore(
        session,
        change,
        // 沒有畫面可拍：不拍，[play] 時照常處理。
        onMissing: _end,
        then: () {
          restore();
          // 「之前」也是骨架最深的畫面：之後的混合改用它，先拍的那張放掉，
          // 進場只多佔一張「只有底色」的圖。
          final skeleton = _skeleton;
          setState(() {
            _phase = _Phase.captured;
            _skeleton = null;
          });
          skeleton?.dispose();
          _afterFrame(() {
            if (!_current(session)) return;
            _captured = null;
            captured.complete();
          });
        },
      ),
    );
    return captured.future;
  }

  Future<void> _play(
    VoidCallback change,
    Duration duration,
    bool sweep,
    Duration gap,
    VoidCallback? settle,
  ) {
    // 換場開始：骨架的混合到此為止，「之前」那張圖接著畫。
    _releaseSkeleton();
    final session = _session;
    final ready = session != null && _phase == _Phase.captured;
    if (!ready || MediaQuery.disableAnimationsOf(context)) _end();
    if (MediaQuery.disableAnimationsOf(context)) {
      change();
      return Future<void>.value();
    }
    final run = _run = Completer<void>();
    _sweep = sweep;
    _gap = gap;
    _settle = settle;
    _progress.duration = duration;
    if (ready) {
      // 兩張圖已經拍好：螢幕換上「之前」那張圖，底下同一格換成換好的樣子
      // （螢幕上看不到，換回真的畫面時已經好了）。
      change();
      _showBefore(session);
      return run.future;
    }
    final fresh = _session = Object();
    _afterFrame(
      () => _captureBefore(
        fresh,
        change,
        // 還沒畫出來（或已經拆掉）：沒有「之前」可拍，直接換。
        onMissing: () {
          _end();
          change();
        },
        then: () => _showBefore(fresh),
      ),
    );
    return run.future;
  }

  /// 開始畫兩張圖的混合（換場進度 0，就是「之前」那張圖）；這一格畫完才做
  /// settle、才開始算 gap：settle 落在靜止的畫面上，做得再久，換場前也照樣
  /// 停滿 gap。等的是下一格（[_afterFrame]），不用 endOfFrame：這一格裡別人
  /// 先要過的話，拿到的是這一格的結束。
  void _showBefore(Object session) {
    _progress.value = 0;
    setState(() => _phase = _Phase.playing);
    _afterFrame(() => _settleThenHold(session));
  }

  /// 下一格畫完時做 [action]（[action] 自己判斷能不能做，不能就再等一格）。
  void _afterFrame(VoidCallback action) {
    SchedulerBinding.instance
      ..addPostFrameCallback((_) => action())
      ..ensureVisualUpdate();
  }

  /// 照一般畫畫面的方式把底下畫成圖。不用 toImageSync：它走另一條畫法，
  /// 半透明的地方（玻璃、細進度線的底）和螢幕上差 1 階，換場結束換回真的
  /// 畫面那一格，這些地方整片跳一下（2026-10-26 量到，一般的畫法和螢幕上
  /// 一模一樣）。圖要等一下才拿得到，這段時間畫面停著。
  Future<ui.Image> _toImage(RenderRepaintBoundary boundary) =>
      boundary.toImage(pixelRatio: _pixelRatio);

  /// 拍下「之前」，[change] 換成換好的樣子（螢幕上蓋著「之前」），畫好後拍下
  /// 「之後」，再 [then]。沒有畫面可拍時 [onMissing]。
  void _captureBefore(
    Object session,
    VoidCallback change, {
    required VoidCallback onMissing,
    required VoidCallback then,
  }) {
    if (!_current(session)) return;
    final boundary = _boundary;
    if (boundary == null) {
      onMissing();
      return;
    }
    if (!_readyToCapture(boundary)) {
      _afterFrame(
        () => _captureBefore(session, change, onMissing: onMissing, then: then),
      );
      return;
    }
    unawaited(
      _toImage(boundary).then((before) {
        if (!_current(session)) {
          before.dispose();
          return;
        }
        // 換成換好的樣子；這一格（與拍「之後」之前的每一格）螢幕上蓋著
        // 「之前」，底下重建得再久也看不出來。
        change();
        setState(() {
          _before = before;
          _phase = _Phase.holding;
        });
        _afterFrame(() => _captureAfter(session, then));
      }),
    );
  }

  void _captureAfter(Object session, VoidCallback then) {
    if (!_current(session)) return;
    final boundary = _boundary;
    if (boundary == null) {
      _end();
      return;
    }
    if (!_readyToCapture(boundary)) {
      _afterFrame(() => _captureAfter(session, then));
      return;
    }
    unawaited(
      _toImage(boundary).then((after) {
        if (!_current(session)) {
          after.dispose();
          return;
        }
        _after = after;
        then();
      }),
    );
  }

  void _settleThenHold(Object session) {
    bool current() => _current(session) && _phase == _Phase.playing;
    if (!current()) return;
    final settle = _settle;
    _settle = null;
    settle?.call();
    // settle 裡可能結束或換掉了這一次換場。
    if (!current()) return;
    _hold = Timer(_gap, () => _start(session));
  }

  /// 兩張圖都拍好、也停滿 gap 時開始換場。
  void _start(Object session) {
    if (!_current(session) ||
        _phase != _Phase.playing ||
        _progress.isAnimating) {
      return;
    }
    // 從下一格開始計時：拍圖這幾格多花的時間不吃掉換場的開頭。
    unawaited(
      _progress.forward(from: 0).whenComplete(() {
        if (identical(_session, session)) _end();
      }),
    );
  }

  /// 換回真的畫面、放掉兩張圖，完成這一次換場（拍到一半或拍好還沒播的也
  /// 一起結束）。
  void _end({bool rebuild = true}) {
    final run = _run, captured = _captured;
    _run = null;
    _captured = null;
    _session = null;
    _settle = null;
    _hold?.cancel();
    _hold = null;
    _progress.stop();
    final before = _before, after = _after;
    void reset() {
      _phase = _Phase.live;
      _before = null;
      _after = null;
    }

    if (rebuild && mounted && _phase != _Phase.live) {
      setState(reset);
    } else {
      reset();
    }
    // 已經交出去的畫面各自留著圖的參照，這裡放掉的只是自己這一份。
    before?.dispose();
    after?.dispose();
    run?.complete();
    captured?.complete();
  }

  double get _pixelRatio => MediaQuery.devicePixelRatioOf(context);

  /// 兩張圖和畫面大小對不上了：結束這一次換場、換回真的畫面。
  void _onStale() {
    if (mounted && _phase == _Phase.playing) _end();
  }

  @override
  Widget build(BuildContext context) {
    final mixing = _mixTick != null;
    return _SnapshotSweepPaint(
      phase: _phase,
      before: _before,
      after: _after,
      progress: _progress,
      sweep: _sweep,
      pixelRatio: _pixelRatio,
      onStale: _onStale,
      cover: _cover,
      mixBase: mixing ? _base : null,
      // 換場的兩張圖拍好後，「之前」就是骨架最深的畫面（[_capture]）。
      mixSkeleton: mixing
          ? (_phase == _Phase.captured ? _before : null) ?? _skeleton
          : null,
      mixTick: _mixTick,
      mixDepth: _mixDepth,
      child: RepaintBoundary(key: _boundaryKey, child: widget.child),
    );
  }
}

class _SnapshotSweepPaint extends SingleChildRenderObjectWidget {
  const _SnapshotSweepPaint({
    required this.phase,
    required this.before,
    required this.after,
    required this.progress,
    required this.sweep,
    required this.pixelRatio,
    required this.onStale,
    required this.cover,
    required this.mixBase,
    required this.mixSkeleton,
    required this.mixTick,
    required this.mixDepth,
    required super.child,
  });

  final _Phase phase;
  final ui.Image? before;
  final ui.Image? after;
  final Animation<double> progress;
  final bool sweep;
  final double pixelRatio;
  final VoidCallback onStale;
  final ui.Image? cover;
  final ui.Image? mixBase;
  final ui.Image? mixSkeleton;
  final Listenable? mixTick;
  final double Function(double u)? mixDepth;

  @override
  _RenderSnapshotSweep createRenderObject(BuildContext context) =>
      _RenderSnapshotSweep(progress, onStale)
        ..phase = phase
        ..before = before
        ..after = after
        ..sweep = sweep
        ..pixelRatio = pixelRatio
        ..cover = cover
        ..mixBase = mixBase
        ..mixSkeleton = mixSkeleton
        ..mixTick = mixTick
        ..mixDepth = mixDepth;

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSnapshotSweep renderObject,
  ) {
    renderObject
      ..phase = phase
      ..before = before
      ..after = after
      ..sweep = sweep
      ..pixelRatio = pixelRatio
      ..onStale = onStale
      ..cover = cover
      ..mixBase = mixBase
      ..mixSkeleton = mixSkeleton
      ..mixTick = mixTick
      ..mixDepth = mixDepth;
  }
}

class _RenderSnapshotSweep extends RenderProxyBox {
  _RenderSnapshotSweep(this._progress, this.onStale);

  final Animation<double> _progress;

  /// 兩張圖和畫面大小對不上時呼叫：結束這一次換場。
  VoidCallback onStale;

  /// 拍圖用的裝置像素比，用來判斷兩張圖還對不對得上畫面。
  double _pixelRatio = 1;
  set pixelRatio(double value) {
    if (_pixelRatio == value) return;
    _pixelRatio = value;
    markNeedsPaint();
  }

  _Phase _phase = _Phase.live;
  set phase(_Phase value) {
    if (_phase == value) return;
    _phase = value;
    markNeedsPaint();
  }

  ui.Image? _before;
  set before(ui.Image? value) {
    if (identical(_before, value)) return;
    _before = value;
    markNeedsPaint();
  }

  ui.Image? _after;
  set after(ui.Image? value) {
    if (identical(_after, value)) return;
    _after = value;
    markNeedsPaint();
  }

  bool _sweep = true;
  set sweep(bool value) {
    if (_sweep == value) return;
    _sweep = value;
    markNeedsPaint();
  }

  /// 拍骨架那幾格蓋在螢幕上的圖（[SnapshotSweepController.captureSkeleton]）。
  ui.Image? _cover;
  set cover(ui.Image? value) {
    if (identical(_cover, value)) return;
    _cover = value;
    markNeedsPaint();
  }

  /// 骨架混合（[SnapshotSweepController.mixSkeleton]）的兩張圖；有這兩張和
  /// [_mixDepth] 時螢幕上畫混合，不畫底下。
  ui.Image? _mixBase;
  set mixBase(ui.Image? value) {
    if (identical(_mixBase, value)) return;
    _mixBase = value;
    markNeedsPaint();
  }

  ui.Image? _mixSkeleton;
  set mixSkeleton(ui.Image? value) {
    if (identical(_mixSkeleton, value)) return;
    _mixSkeleton = value;
    markNeedsPaint();
  }

  Listenable? _mixTick;
  set mixTick(Listenable? value) {
    if (identical(_mixTick, value)) return;
    if (attached) _mixTick?.removeListener(markNeedsPaint);
    _mixTick = value;
    if (attached) _mixTick?.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  double Function(double u)? _mixDepth;
  set mixDepth(double Function(double u)? value) {
    if (identical(_mixDepth, value)) return;
    _mixDepth = value;
    markNeedsPaint();
  }

  void _onTick() {
    if (_phase == _Phase.playing) markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _progress.addListener(_onTick);
    _mixTick?.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _progress.removeListener(_onTick);
    _mixTick?.removeListener(markNeedsPaint);
    super.detach();
  }

  // 換場每一格只重畫這一層，不牽動外面。
  @override
  bool get isRepaintBoundary => true;

  /// 換場中不接點擊與捲動：底下的畫面沒有畫出來，點到的會是看不到的東西。
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (_phase == _Phase.live || _phase == _Phase.captured) {
      return super.hitTest(result, position: position);
    }
    if (!size.contains(position)) return false;
    result.add(BoxHitTestEntry(this, position));
    return true;
  }

  static final Paint _exact = Paint()..filterQuality = FilterQuality.none;

  /// 換場時每種透明度的畫筆（[_paintMix]），第一次用到才建、之後一直重用：
  /// 換場每一格最多畫 254 段，每段新建一支畫筆的話，0.6 秒的換場裡新生區
  /// 會滿兩次，Dart 在換場途中回收（2026-10-28 量到）。
  static final List<Paint?> _faded = List<Paint?>.filled(255, null);

  static Paint _fadedPaint(int alpha) => Paint()
    ..filterQuality = FilterQuality.none
    ..color = Color.fromARGB(alpha, 0, 0, 0);

  @override
  void paint(PaintingContext context, Offset offset) {
    final before = _before;
    final after = _after;
    switch (_phase) {
      case _Phase.live:
      case _Phase.captured:
        final base = _mixBase, skeleton = _mixSkeleton, depth = _mixDepth;
        if (base != null &&
            skeleton != null &&
            depth != null &&
            _fits(base) &&
            _fits(skeleton)) {
          _paintDepth(context.canvas, offset, base, skeleton, depth);
          return;
        }
        super.paint(context, offset);
        final cover = _cover;
        if (cover != null && _fits(cover)) {
          _drawWhole(context.canvas, cover, offset);
        }
      case _Phase.holding:
        // 底下畫的是換好的樣子（為了拍下來），上面蓋著「之前」。
        super.paint(context, offset);
        if (before != null) _drawWhole(context.canvas, before, offset);
      case _Phase.playing:
        if (before == null ||
            after == null ||
            !_fits(before) ||
            !_fits(after)) {
          // 畫面大小在換場中變了：畫真的畫面，這一格畫完就結束換場。
          super.paint(context, offset);
          SchedulerBinding.instance.addPostFrameCallback((_) => onStale());
          return;
        }
        _paintMix(context.canvas, offset, before, after, _progress.value);
    }
  }

  void _drawWhole(Canvas canvas, ui.Image image, Offset offset) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      offset & size,
      _exact,
    );
  }

  /// 兩張圖照畫面現在的大小拍的：大小變了（旋轉、視窗縮放）就對不上。
  bool _fits(ui.Image image) =>
      image.width == (size.width * _pixelRatio).ceil() &&
      image.height == (size.height * _pixelRatio).ceil();

  /// 之前那張整片畫上，之後那張照每一行像素的濃度疊上去，等於兩張照濃度
  /// 混合。濃度先換成 8 位元的透明度，透明度相同、相鄰的行合成一段，每段
  /// 一次 [Canvas.drawImageRect]、用畫筆的透明度（兩種繪圖引擎行為一致的
  /// 畫法）；已經換好的部分只畫之後、還沒開始的只畫之前，不另開圖層。透明度
  /// 只有 256 種，正在換的那一段最多 254 段。
  void _paintMix(
    Canvas canvas,
    Offset offset,
    ui.Image before,
    ui.Image after,
    double progress,
  ) {
    final width = after.width;
    final height = after.height.toDouble();
    final scale = size.width / width;
    Rect columns(int from, int to) =>
        Rect.fromLTWH(from.toDouble(), 0, (to - from).toDouble(), height);
    Rect onScreen(int from, int to) => Rect.fromLTWH(
      offset.dx + from * scale,
      offset.dy,
      (to - from) * scale,
      size.height,
    );
    void draw(ui.Image image, int from, int to, int alpha) {
      if (to <= from || alpha <= 0) return;
      canvas.drawImageRect(
        image,
        columns(from, to),
        onScreen(from, to),
        alpha >= 255 ? _exact : _faded[alpha] ??= _fadedPaint(alpha),
      );
    }

    int alphaAt(int x) =>
        (SkeletonReveal.incomingOpacityAt(
                  progress,
                  (x + 0.5) / width,
                  sweep: _sweep,
                ) *
                255)
            .round();

    // 濃度由左往右遞減：[0, done) 已經換好，之後的才要畫之前那張。
    var done = 0;
    while (done < width && alphaAt(done) >= 255) {
      done++;
    }
    draw(before, done, width, 255);
    draw(after, 0, done, 255);
    var from = done;
    while (from < width) {
      final alpha = alphaAt(from);
      if (alpha <= 0) break;
      var to = from + 1;
      while (to < width && alphaAt(to) == alpha) {
        to++;
      }
      draw(after, from, to, alpha);
      from = to;
    }
  }

  /// 每一行像素的透明度（[_paintDepth]），照圖的寬度建一次、每一格重用：
  /// 呼吸每一格都要算一次，不每格新建。
  Uint8List _alphas = Uint8List(0);

  /// [base] 整片畫上，[skeleton] 照每一行像素的深淺 [depthAt] 疊上去：
  /// 底色 +（骨架 − 底色）× 深淺。深淺先換成 8 位元的透明度，透明度相同、
  /// 相鄰的行合成一段，每段一次 [Canvas.drawImageRect]（同 [_paintMix]）；
  /// 深淺不必由左往右遞減（呼吸是一道明暗走過去）。
  void _paintDepth(
    Canvas canvas,
    Offset offset,
    ui.Image base,
    ui.Image skeleton,
    double Function(double u) depthAt,
  ) {
    final width = skeleton.width;
    final height = skeleton.height.toDouble();
    final scale = size.width / width;
    if (_alphas.length != width) _alphas = Uint8List(width);
    final alphas = _alphas;
    for (var x = 0; x < width; x++) {
      alphas[x] = (depthAt((x + 0.5) / width).clamp(0.0, 1.0) * 255).round();
    }
    _drawWhole(canvas, base, offset);
    var from = 0;
    while (from < width) {
      final alpha = alphas[from];
      var to = from + 1;
      while (to < width && alphas[to] == alpha) {
        to++;
      }
      if (alpha > 0) {
        canvas.drawImageRect(
          skeleton,
          Rect.fromLTWH(from.toDouble(), 0, (to - from).toDouble(), height),
          Rect.fromLTWH(
            offset.dx + from * scale,
            offset.dy,
            (to - from) * scale,
            size.height,
          ),
          alpha >= 255 ? _exact : _faded[alpha] ??= _fadedPaint(alpha),
        );
      }
      from = to;
    }
  }
}
