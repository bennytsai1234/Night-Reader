import 'dart:async';
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
/// 看起來不動），換場期間多佔兩張螢幕大小的圖，也不接點擊與捲動。
///
/// 包在要換場的範圍外面（例如整個主頁面）；要換場的地方用 [controller] 的
/// [SnapshotSweepController.play]。
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

  /// 正在換場：拍圖或兩張圖混合中。
  bool get isPlaying => (_state?._phase ?? _Phase.live) != _Phase.live;

  /// 兩張圖混合的進度（經過的時間比例）；不在混合時為 null。
  double? get progress {
    final state = _state;
    if (state == null || state._phase != _Phase.playing) return null;
    return state._progress.value;
  }

  /// 拍下現在的畫面，呼叫 [change] 把底下換成換好的樣子，下一格畫好後拍下
  /// 來，再花 [duration] 把之前換成之後：[sweep] 時由左而右（同
  /// [SkeletonReveal.incomingOpacityAt]），否則整片淡換。換場播完、換回真的
  /// 畫面時完成。
  ///
  /// 不在 [SnapshotSweep] 底下，或系統要求減少動態時，直接 [change]。
  Future<void> play({
    required VoidCallback change,
    required Duration duration,
    bool sweep = true,
  }) {
    final state = _state;
    if (state == null || !state.mounted) {
      change();
      return Future<void>.value();
    }
    return state._play(change, duration, sweep);
  }

  /// 換場還沒播完就換回真的畫面（底下已經換好），完成這一次換場。建畫面
  /// 途中呼叫時（例如底下的元件在 didUpdateWidget 裡）等這一幀畫完再換。
  void finish() {
    final state = _state;
    final run = state?._run;
    if (state == null || run == null) return;
    final scheduler = SchedulerBinding.instance;
    if (scheduler.schedulerPhase != SchedulerPhase.persistentCallbacks) {
      state._end();
      return;
    }
    scheduler.addPostFrameCallback((_) {
      if (state.mounted && identical(state._run, run)) state._end();
    });
  }
}

enum _Phase {
  /// 畫真的畫面。
  live,

  /// 已經拍好「之前」、底下換成了換好的樣子：螢幕上蓋著「之前」那張圖，
  /// 等底下畫好拍「之後」。
  holding,

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

  /// 這一次換場；換場被下一次蓋過或結束時換掉。
  Completer<void>? _run;

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
    _progress.dispose();
    super.dispose();
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

  Future<void> _play(VoidCallback change, Duration duration, bool sweep) {
    _end();
    if (MediaQuery.disableAnimationsOf(context)) {
      change();
      return Future<void>.value();
    }
    final run = _run = Completer<void>();
    _sweep = sweep;
    _progress.duration = duration;
    _afterFrame(() => _captureBefore(run, change));
    return run.future;
  }

  /// 下一格畫完時做 [action]（[action] 自己判斷能不能做，不能就再等一格）。
  void _afterFrame(VoidCallback action) {
    SchedulerBinding.instance
      ..addPostFrameCallback((_) => action())
      ..ensureVisualUpdate();
  }

  void _captureBefore(Completer<void> run, VoidCallback change) {
    if (!mounted || !identical(_run, run)) return;
    final boundary = _boundary;
    if (boundary == null) {
      // 還沒畫出來（或已經拆掉）：沒有「之前」可拍，直接換。
      _run = null;
      change();
      run.complete();
      return;
    }
    if (!_readyToCapture(boundary)) {
      _afterFrame(() => _captureBefore(run, change));
      return;
    }
    final before = boundary.toImageSync(pixelRatio: _pixelRatio);
    // 換成換好的樣子；這一格（與拍「之後」之前的每一格）螢幕上蓋著「之前」，
    // 底下重建得再久也看不出來。
    change();
    setState(() {
      _before = before;
      _phase = _Phase.holding;
    });
    _afterFrame(() => _captureAfter(run));
  }

  void _captureAfter(Completer<void> run) {
    if (!mounted || !identical(_run, run)) return;
    final boundary = _boundary;
    if (boundary == null) {
      _end();
      return;
    }
    if (!_readyToCapture(boundary)) {
      _afterFrame(() => _captureAfter(run));
      return;
    }
    final after = boundary.toImageSync(pixelRatio: _pixelRatio);
    setState(() {
      _after = after;
      _phase = _Phase.playing;
    });
    // 從下一格開始計時：拍圖這幾格多花的時間不吃掉換場的開頭。
    unawaited(
      _progress.forward(from: 0).whenComplete(() {
        if (identical(_run, run)) _end();
      }),
    );
  }

  /// 換回真的畫面、放掉兩張圖，完成這一次換場。
  void _end({bool rebuild = true}) {
    final run = _run;
    _run = null;
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
  }

  double get _pixelRatio => MediaQuery.devicePixelRatioOf(context);

  @override
  Widget build(BuildContext context) => _SnapshotSweepPaint(
    phase: _phase,
    before: _before,
    after: _after,
    progress: _progress,
    sweep: _sweep,
    child: RepaintBoundary(key: _boundaryKey, child: widget.child),
  );
}

class _SnapshotSweepPaint extends SingleChildRenderObjectWidget {
  const _SnapshotSweepPaint({
    required this.phase,
    required this.before,
    required this.after,
    required this.progress,
    required this.sweep,
    required super.child,
  });

  final _Phase phase;
  final ui.Image? before;
  final ui.Image? after;
  final Animation<double> progress;
  final bool sweep;

  @override
  _RenderSnapshotSweep createRenderObject(BuildContext context) =>
      _RenderSnapshotSweep(progress)
        ..phase = phase
        ..before = before
        ..after = after
        ..sweep = sweep;

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSnapshotSweep renderObject,
  ) {
    renderObject
      ..phase = phase
      ..before = before
      ..after = after
      ..sweep = sweep;
  }
}

class _RenderSnapshotSweep extends RenderProxyBox {
  _RenderSnapshotSweep(this._progress);

  final Animation<double> _progress;

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

  void _onTick() {
    if (_phase == _Phase.playing) markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _progress.addListener(_onTick);
  }

  @override
  void detach() {
    _progress.removeListener(_onTick);
    super.detach();
  }

  // 換場每一格只重畫這一層，不牽動外面。
  @override
  bool get isRepaintBoundary => true;

  /// 換場中不接點擊與捲動：底下的畫面沒有畫出來，點到的會是看不到的東西。
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (_phase == _Phase.live) {
      return super.hitTest(result, position: position);
    }
    if (!size.contains(position)) return false;
    result.add(BoxHitTestEntry(this, position));
    return true;
  }

  static final Paint _exact = Paint()..filterQuality = FilterQuality.none;

  @override
  void paint(PaintingContext context, Offset offset) {
    final before = _before;
    final after = _after;
    switch (_phase) {
      case _Phase.live:
        super.paint(context, offset);
      case _Phase.holding:
        // 底下畫的是換好的樣子（為了拍下來），上面蓋著「之前」。
        super.paint(context, offset);
        if (before != null) _drawWhole(context.canvas, before, offset);
      case _Phase.playing:
        if (before == null || after == null) {
          super.paint(context, offset);
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

  /// 每一行像素：之後那張照該行的濃度疊在之前那張上，等於兩張照濃度混合。
  /// 已經換好的部分只畫之後、還沒開始的部分只畫之前，正在換的那一段一行
  /// 一行疊（一次 [Canvas.drawAtlas]），不另開圖層。
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
    if (!_sweep) {
      final alpha = SkeletonReveal.incomingOpacityAt(progress, 0, sweep: false);
      _drawWhole(canvas, before, offset);
      if (alpha > 0) {
        canvas.drawImageRect(
          after,
          Rect.fromLTWH(0, 0, width.toDouble(), height),
          offset & size,
          Paint()
            ..filterQuality = FilterQuality.none
            ..color = Color.fromRGBO(0, 0, 0, alpha),
        );
      }
      return;
    }
    // 濃度由左往右遞減：[0, done) 已經換好、[done, untouched) 正在換。
    var done = width;
    var untouched = width;
    final alphas = <int>[];
    for (var x = 0; x < width; x++) {
      final alpha = SkeletonReveal.incomingOpacityAt(
        progress,
        (x + 0.5) / width,
      );
      final byte = (alpha * 255).round();
      if (byte >= 255) continue;
      if (done == width) done = x;
      if (byte <= 0) {
        untouched = x;
        break;
      }
      alphas.add(byte);
    }
    Rect columns(int from, int to) =>
        Rect.fromLTWH(from.toDouble(), 0, (to - from).toDouble(), height);
    Rect onScreen(int from, int to) => Rect.fromLTWH(
      offset.dx + from * scale,
      offset.dy,
      (to - from) * scale,
      size.height,
    );
    if (done < width) {
      canvas.drawImageRect(
        before,
        columns(done, width),
        onScreen(done, width),
        _exact,
      );
    }
    if (done > 0) {
      canvas.drawImageRect(after, columns(0, done), onScreen(0, done), _exact);
    }
    if (alphas.isEmpty) return;
    canvas.drawAtlas(
      after,
      [
        for (var i = 0; i < alphas.length; i++)
          RSTransform.fromComponents(
            rotation: 0,
            scale: scale,
            anchorX: 0,
            anchorY: 0,
            translateX: offset.dx + (done + i) * scale,
            translateY: offset.dy,
          ),
      ],
      [
        for (var i = 0; i < alphas.length; i++)
          Rect.fromLTWH((done + i).toDouble(), 0, 1, height),
      ],
      [for (final alpha in alphas) Color.fromARGB(alpha, 255, 255, 255)],
      BlendMode.srcIn,
      null,
      _exact,
    );
    assert(done + alphas.length == untouched || untouched == width);
  }
}
