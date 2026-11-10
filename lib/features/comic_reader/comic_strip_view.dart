import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/scheduler.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';

import 'comic_chapter_transition.dart';
import 'comic_page_image.dart';
import 'comic_strip_model.dart';

/// 畫面頂端讀到哪：第幾話第幾張，在那張的幾成。
@immutable
class ComicLocation {
  const ComicLocation(this.chapterIndex, this.pageIndex, {this.fraction = 0});

  final int chapterIndex;
  final int pageIndex;

  /// 畫面頂端在這張圖的位置，0 是頂、1 是底。
  final double fraction;

  @override
  bool operator ==(Object other) =>
      other is ComicLocation &&
      other.chapterIndex == chapterIndex &&
      other.pageIndex == pageIndex &&
      other.fraction == fraction;

  @override
  int get hashCode => Object.hash(chapterIndex, pageIndex, fraction);

  @override
  String toString() => 'ComicLocation($chapterIndex, $pageIndex, $fraction)';
}

/// 點擊區域（照 Mihon 的 L 形 `LNavigation`）。
enum ComicTapRegion { previous, menu, next }

/// 條漫上的點擊區域：上排與左中是上一屏，右中與下排是下一屏，正中間是選單。
ComicTapRegion comicTapRegionOf(Offset position, Size size) {
  final x = position.dx / size.width;
  final y = position.dy / size.height;
  if (y < 0.33) return ComicTapRegion.previous;
  if (y >= 0.66) return ComicTapRegion.next;
  if (x < 0.33) return ComicTapRegion.previous;
  if (x >= 0.66) return ComicTapRegion.next;
  return ComicTapRegion.menu;
}

/// 外面對條漫下的指令：往上下捲一屏、自動捲動。
class ComicStripController {
  _ComicStripViewState? _state;

  /// 往下（[forward]）或往上捲一屏的四分之三（同 Mihon）。
  void scrollByScreen({required bool forward}) =>
      _state?._scrollByScreen(forward: forward);

  /// 每秒往下捲幾個螢幕高；0 是停。捲到底或使用者碰了畫面時自己停下，
  /// 呼叫 [onAutoScrollStopped]。
  void setAutoScroll(double screensPerSecond) =>
      _state?._setAutoScroll(screensPerSecond);

  VoidCallback? onAutoScrollStopped;
}

/// 漫畫閱讀器的條漫（ADR 0052、`docs/design/comics.md`）：一話的圖由上往下
/// 接成一長條，撐滿寬度、圖與圖之間不留縫，換章分隔夾在兩話之間；只直向
/// 捲動，雙指 0.5–3 倍縮放，點兩下在原本大小時以點的位置放大到 2 倍、其他
/// 大小時回到原本大小（200ms）。手感照 Mihon 的 `WebtoonRecyclerView`。
///
/// 縮放的做法：捲動清單的可視高度是螢幕高 ÷ 倍率，整塊放大到螢幕高，左右
/// 用平移看放大後超出的部分；垂直不用平移，捲動本身就是。
///
/// 捲動的手勢自己處理（清單本身不收拖動），單指拖動交給捲動位置的
/// `drag`，放開照原本的物理慣性滑；雙指只縮放與平移。
class ComicStripView extends StatefulWidget {
  const ComicStripView({
    super.key,
    required this.model,
    required this.foreground,
    required this.accent,
    required this.onLocation,
    required this.onTap,
    required this.titleOf,
    required this.gapBetween,
    this.controller,
    this.initialFraction = 0,
    this.webUrlOpener,
  });

  final ComicStripModel model;
  final Color foreground;
  final Color accent;

  /// 畫面頂端讀到的地方變了。
  final ValueChanged<ComicLocation> onLocation;

  /// 點了一下（已扣掉點兩下）。點擊區域由呼叫端決定要做什麼。
  final ValueChanged<ComicTapRegion> onTap;

  /// 第幾話的章名。
  final String Function(int chapterIndex) titleOf;

  /// 從第 from 話接到第 to 話中間缺幾話。
  final int Function(int from, int to) gapBetween;
  final ComicStripController? controller;

  /// 開書時錨點那張圖捲到幾成。
  final double initialFraction;

  /// 載入失敗的「用網頁開啟」。
  final void Function(String url)? webUrlOpener;

  static const double minScale = 0.5;
  static const double maxScale = 3;
  static const double doubleTapScale = 2;
  static const Duration zoomDuration = Duration(milliseconds: 200);

  /// 失敗的那一張佔螢幕高的比例。
  static const double failedPageHeight = 0.8;

  @override
  State<ComicStripView> createState() => _ComicStripViewState();
}

class _ComicStripViewState extends State<ComicStripView>
    with TickerProviderStateMixin {
  final GlobalKey _centerKey = GlobalKey(debugLabel: 'comic-anchor');
  _ComicScrollController? _scrollController;
  int _generation = -1;
  double? _pendingFraction;

  Size _screen = Size.zero;
  double _scale = 1;
  double _tx = 0;

  // 每一塊的高度，往下與往上各一份累計（[_after] 第 i 塊從 _afterTops[i]
  // 開始；[_before] 第 i 塊往上佔 _beforeEnds[i] 到 _beforeEnds[i + 1]）。
  List<double> _afterTops = const [0];
  List<double> _beforeEnds = const [0];
  final Map<ComicTransitionItem, (Object, double)> _transitionExtents = {};
  final Map<ComicPageItem, bool> _failedPages = {};

  Drag? _drag;
  int _pointers = 0;
  double _baseScale = 1;
  Offset _focalContent = Offset.zero;
  bool _tapStoppedScroll = false;
  Offset? _doubleTapAt;
  AnimationController? _zoomAnimation;
  AnimationController? _panAnimation;
  Ticker? _autoScroll;
  double _autoScrollSpeed = 0;
  Duration _autoScrollLast = Duration.zero;
  ComicLocation? _lastLocation;

  @override
  void initState() {
    super.initState();
    widget.controller?._state = this;
    widget.model.addListener(_onModel);
    _resetScroll(widget.initialFraction);
  }

  @override
  void didUpdateWidget(ComicStripView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller?._state = null;
      widget.controller?._state = this;
    }
    if (!identical(oldWidget.model, widget.model)) {
      oldWidget.model.removeListener(_onModel);
      widget.model.addListener(_onModel);
      _resetScroll(0);
    }
  }

  @override
  void dispose() {
    widget.controller?._state = null;
    widget.model.removeListener(_onModel);
    _zoomAnimation?.dispose();
    _panAnimation?.dispose();
    _autoScroll?.dispose();
    _scroll.dispose();
    super.dispose();
  }

  ComicStripModel get _model => widget.model;

  _ComicScrollController get _scroll => _scrollController!;

  /// 跳章後換一個捲動位置（條漫整個換了內容），舊的等這一幀畫完再丟。
  void _resetScroll(double fraction) {
    _generation = _model.generation;
    _pendingFraction = fraction > 0 ? fraction : null;
    final old = _scrollController;
    _scrollController = _ComicScrollController()..addListener(_onScroll);
    if (old != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
  }

  void _onModel() {
    if (!mounted) return;
    if (_model.generation != _generation) {
      _stopAutoScroll();
      _resetScroll(0);
    }
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _applyPendingFraction();
      _onScroll();
    });
  }

  // ─── 高度 ───────────────────────────────────────────────────────────

  double get _width => _screen.width;

  /// 捲動清單的可視高度：螢幕高 ÷ 倍率。
  double get _viewportHeight => _screen.height / _scale;

  double _extentOf(ComicStripItem item) {
    switch (item) {
      case ComicPageItem():
        if (_failedPages[item] == true) {
          return _screen.height * ComicStripView.failedPageHeight;
        }
        return _width * _model.aspectRatioOf(item);
      case ComicChapterPlaceholderItem():
        return _model.stateOf(item.chapterIndex) is ComicChapterFailed
            ? _screen.height
            : _width * ComicStripModel.defaultAspectRatio;
      case ComicTransitionItem():
        final content = _transitionContent(item);
        final signature = Object.hash(
          content.fromTitle,
          content.toTitle,
          content.gap,
          content.status.runtimeType,
          content.status is ComicTransitionFailed
              ? (content.status as ComicTransitionFailed).message
              : null,
          _width,
          MediaQuery.textScalerOf(context),
        );
        final cached = _transitionExtents[item];
        if (cached != null && cached.$1 == signature) return cached.$2;
        final extent = ComicChapterTransition.extentOf(
          content,
          width: _width,
          textScaler: MediaQuery.textScalerOf(context),
          base: DefaultTextStyle.of(context).style,
        );
        _transitionExtents[item] = (signature, extent);
        return extent;
    }
  }

  ComicTransitionContent _transitionContent(ComicTransitionItem item) {
    final pending = _model.pendingChapterOf(item);
    final ComicTransitionStatus status = switch (pending == null
        ? const ComicChapterReady([])
        : _model.stateOf(pending)) {
      ComicChapterFailed(:final error) => ComicTransitionFailed(
        ComicLoadError.describe(error),
      ),
      ComicChapterReady() => const ComicTransitionIdle(),
      // 還沒開始載或正在載。
      _ => const ComicTransitionLoading(),
    };
    final from = item.from;
    final to = item.to;
    return ComicTransitionContent(
      fromTitle: from == null ? null : _titleOf(from),
      toTitle: to == null ? null : _titleOf(to),
      gap: from != null && to != null ? _gapOf(from, to) : 0,
      status: status,
    );
  }

  String _titleOf(int index) => widget.titleOf(index);

  int _gapOf(int from, int to) => widget.gapBetween(from, to);

  void _measure() {
    var top = 0.0;
    final tops = <double>[0];
    for (final item in _model.after) {
      top += _extentOf(item);
      tops.add(top);
    }
    var end = 0.0;
    final ends = <double>[0];
    for (final item in _model.before) {
      end += _extentOf(item);
      ends.add(end);
    }
    _afterTops = tops;
    _beforeEnds = ends;
  }

  // ─── 位置 ───────────────────────────────────────────────────────────

  void _applyPendingFraction() {
    final fraction = _pendingFraction;
    if (fraction == null || !_scroll.hasClients) return;
    final after = _model.after;
    if (after.isEmpty || after.first is! ComicPageItem) return;
    _pendingFraction = null;
    _scroll.jumpTo(fraction * (_afterTops[1] - _afterTops[0]));
  }

  /// 捲動位置 [pixels]（畫面頂端）落在哪一塊，以及在那塊裡的距離。用整數
  /// 位置 g：g >= 0 是往下第 g 塊，g < 0 是往上第 -g-1 塊。
  (int, double) _itemAt(double pixels) {
    if (pixels >= 0) {
      final i = _upperBound(_afterTops, pixels) - 1;
      final index = i.clamp(0, math.max(0, _model.after.length - 1)).toInt();
      return (index, pixels - _afterTops[index]);
    }
    final distance = -pixels;
    final k = (_lowerBound(_beforeEnds, distance) - 1)
        .clamp(0, math.max(0, _model.before.length - 1))
        .toInt();
    return (-k - 1, _beforeEnds[k + 1] - distance);
  }

  ComicStripItem? _itemOf(int g) {
    if (g >= 0) return g < _model.after.length ? _model.after[g] : null;
    final k = -g - 1;
    return k < _model.before.length ? _model.before[k] : null;
  }

  double _topOf(int g) => g >= 0 ? _afterTops[g] : -_beforeEnds[-g];

  ComicLocation? _locationAt(double pixels) {
    if (_model.after.isEmpty) return null;
    final (g, within) = _itemAt(pixels);
    final item = _itemOf(g);
    if (item is ComicPageItem) {
      final extent = _extentOf(item);
      return ComicLocation(
        item.chapterIndex,
        item.pageIndex,
        fraction: extent <= 0 ? 0 : (within / extent).clamp(0.0, 1.0),
      );
    }
    if (item is ComicChapterPlaceholderItem) return null;
    // 換章分隔：算下面那一張的開頭，沒有的話上面那一張的結尾。
    if (_itemOf(g + 1) case final ComicPageItem page) {
      return ComicLocation(page.chapterIndex, page.pageIndex);
    }
    if (_itemOf(g - 1) case final ComicPageItem page) {
      return ComicLocation(page.chapterIndex, page.pageIndex, fraction: 1);
    }
    return null;
  }

  void _onScroll() {
    if (!_scroll.hasClients || _screen.isEmpty) return;
    final position = _scroll.position;
    final pixels = position.pixels;
    final location = _locationAt(pixels);
    if (location != null && location != _lastLocation) {
      _lastLocation = location;
      widget.onLocation(location);
    }
    // 離已放上的內容盡頭不到兩個螢幕就接上下一話、上一話。
    final reach = _viewportHeight * 2;
    if (_afterTops.last - (pixels + _viewportHeight) < reach) {
      _model.loadNext();
    }
    if (_beforeEnds.last + pixels < reach) _model.loadPrevious();
  }

  /// 圖到了、或載入失敗改成八成螢幕高：高度變了。畫面頂端看到的內容不動：
  /// 變的那一塊在畫面頂端上面（往下那一側），或在畫面頂端下面（往上那一
  /// 側），捲動位置跟著補回去。
  void _resize(ComicPageItem item, void Function() change) {
    final g = _indexOf(item);
    final before = _extentOf(item);
    change();
    final after = _extentOf(item);
    final delta = after - before;
    if (g == null || delta.abs() < 0.5 || !_scroll.hasClients) {
      setState(() {});
      return;
    }
    final position = _scroll.comicPosition;
    final pixels = position.pixels;
    double? correction;
    if (g >= 0 && _topOf(g) < pixels - 0.5) correction = delta;
    if (g < 0 && _topOf(g) + before > pixels + 0.5) correction = -delta;
    setState(() {});
    if (correction != null) position.shiftBy(correction);
  }

  int? _indexOf(ComicPageItem item) {
    final a = _model.after.indexOf(item);
    if (a >= 0) return a;
    final b = _model.before.indexOf(item);
    return b >= 0 ? -b - 1 : null;
  }

  void _onAspectRatio(ComicPageItem item, double ratio) {
    if (_failedPages[item] != true &&
        (_model.aspectRatioOf(item) - ratio).abs() < 0.001) {
      return;
    }
    _resize(item, () {
      _failedPages.remove(item);
      _model.setAspectRatio(item, ratio);
    });
  }

  void _onPageFailed(ComicPageItem item, bool failed) {
    if ((_failedPages[item] == true) == failed) return;
    _resize(item, () => _failedPages[item] = failed);
  }

  // ─── 手勢 ───────────────────────────────────────────────────────────

  void _onPointerDown(PointerDownEvent event) {
    // 慣性滑動中按下去只停下來，不算點擊（同 Mihon）。
    _tapStoppedScroll = false;
    if (_scroll.hasClients && _scroll.position.isScrollingNotifier.value) {
      _tapStoppedScroll = true;
      if (_drag == null) _scroll.comicPosition.goIdle();
    }
    if (_autoScroll?.isActive ?? false) _stopAutoScroll();
  }

  void _onScaleStart(ScaleStartDetails details) {
    _zoomAnimation?.stop();
    _panAnimation?.stop();
    _pointers = details.pointerCount;
    _beginGesture(details.localFocalPoint, details.focalPoint);
  }

  void _beginGesture(Offset localFocal, Offset globalFocal) {
    _baseScale = _scale;
    if (_pointers >= 2) {
      _drag?.cancel();
      _drag = null;
      _focalContent = _contentAt(localFocal);
    } else if (_scroll.hasClients) {
      _drag = _scroll.position.drag(
        DragStartDetails(
          globalPosition: globalFocal,
          localPosition: localFocal,
        ),
        () => _drag = null,
      );
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount != _pointers) {
      _pointers = details.pointerCount;
      _beginGesture(details.localFocalPoint, details.focalPoint);
      return;
    }
    if (_pointers >= 2) {
      final scale = (_baseScale * details.scale)
          .clamp(ComicStripView.minScale, ComicStripView.maxScale)
          .toDouble();
      _zoomTo(scale, details.localFocalPoint, _focalContent);
      return;
    }
    final delta = details.focalPointDelta;
    if (_scale > 1 && delta.dx != 0) {
      setState(() => _tx = _clampTx(_tx + delta.dx, _scale));
    }
    _drag?.update(
      DragUpdateDetails(
        globalPosition: details.focalPoint,
        localPosition: details.localFocalPoint,
        delta: Offset(0, delta.dy / _scale),
        primaryDelta: delta.dy / _scale,
      ),
    );
  }

  void _onScaleEnd(ScaleEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond;
    final drag = _drag;
    _drag = null;
    if (drag != null) {
      final vy = velocity.dy / _scale;
      drag.end(
        DragEndDetails(
          velocity: Velocity(pixelsPerSecond: Offset(0, vy)),
          primaryVelocity: vy,
        ),
      );
    }
    if (_scale > 1 && velocity.dx.abs() > 50 && _pointers < 2) {
      // 放大時左右甩：照 Mihon 的 zoomFling，0.4 × 速度 ÷ 2、400ms 減速。
      final from = _tx;
      final to = _clampTx(_tx + 0.4 * velocity.dx / 2, _scale);
      final animation = _panAnimation ??= AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 400),
      );
      final curve = CurvedAnimation(
        parent: animation,
        curve: Curves.decelerate,
      );
      void tick() => setState(() => _tx = from + (to - from) * curve.value);
      animation
        ..stop()
        ..value = 0;
      animation.addListener(tick);
      animation.forward().whenCompleteOrCancel(() {
        animation.removeListener(tick);
        curve.dispose();
      });
    }
    _pointers = 0;
  }

  void _onTapUp(TapUpDetails details) {
    if (_tapStoppedScroll) return;
    widget.onTap(comicTapRegionOf(details.localPosition, _screen));
  }

  void _onDoubleTap() {
    final at = _doubleTapAt;
    if (at == null || (_zoomAnimation?.isAnimating ?? false)) return;
    if ((_scale - 1).abs() > 0.001) {
      // 回到原本大小，畫面中間的內容留在中間。
      final center = Offset(_screen.width / 2, _screen.height / 2);
      _animateZoom(1, center, _contentAt(center));
    } else {
      _animateZoom(ComicStripView.doubleTapScale, at, _contentAt(at));
    }
  }

  void _animateZoom(double target, Offset focal, Offset content) {
    final from = _scale;
    final animation = _zoomAnimation ??= AnimationController(
      vsync: this,
      duration: ComicStripView.zoomDuration,
    );
    final curve = CurvedAnimation(parent: animation, curve: Curves.decelerate);
    void tick() =>
        _zoomTo(from + (target - from) * curve.value, focal, content);
    animation
      ..stop()
      ..value = 0;
    animation.addListener(tick);
    animation.forward().whenCompleteOrCancel(() {
      animation.removeListener(tick);
      curve.dispose();
    });
  }

  /// 畫面上 [screen] 這一點對到條漫（未縮放）的哪裡：x 是條漫寬度內的位置，
  /// y 是捲動座標。
  Offset _contentAt(Offset screen) {
    final pixels = _scroll.hasClients ? _scroll.position.pixels : 0.0;
    return Offset((screen.dx - _tx) / _scale, pixels + screen.dy / _scale);
  }

  /// 縮放到 [scale]，條漫上的 [content] 這一點留在畫面上的 [focal]。
  void _zoomTo(double scale, Offset focal, Offset content) {
    final tx = _clampTx(focal.dx - content.dx * scale, scale);
    if (_scroll.hasClients) {
      _scroll.position.jumpTo(content.dy - focal.dy / scale);
    }
    setState(() {
      _scale = scale;
      _tx = tx;
    });
  }

  double _clampTx(double tx, double scale) {
    final width = _screen.width;
    if (scale <= 1) return (width - width * scale) / 2;
    return tx.clamp(width - width * scale, 0.0).toDouble();
  }

  void _scrollByScreen({required bool forward}) {
    if (!_scroll.hasClients) return;
    final distance = _screen.height * 0.75 / _scale;
    final position = _scroll.position;
    final target = (position.pixels + (forward ? distance : -distance))
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    unawaited(
      position.animateTo(
        target,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  // ─── 自動捲動 ───────────────────────────────────────────────────────

  void _setAutoScroll(double screensPerSecond) {
    if (screensPerSecond <= 0) {
      _stopAutoScroll();
      return;
    }
    _autoScrollSpeed = screensPerSecond;
    final ticker = _autoScroll ??= createTicker(_onAutoScrollTick);
    if (!ticker.isActive) {
      _autoScrollLast = Duration.zero;
      ticker.start();
    }
  }

  void _onAutoScrollTick(Duration elapsed) {
    final dt = (elapsed - _autoScrollLast).inMicroseconds / 1e6;
    _autoScrollLast = elapsed;
    if (!_scroll.hasClients || dt <= 0) return;
    final position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent &&
        _model.after.last is ComicTransitionItem &&
        (_model.after.last as ComicTransitionItem).to == null) {
      _stopAutoScroll();
      return;
    }
    position.jumpTo(
      math.min(
        position.maxScrollExtent,
        position.pixels + _autoScrollSpeed * _screen.height * dt / _scale,
      ),
    );
  }

  void _stopAutoScroll() {
    final ticker = _autoScroll;
    if (ticker == null || !ticker.isActive) return;
    ticker.stop();
    widget.controller?.onAutoScrollStopped?.call();
  }

  // ─── 畫面 ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screen = constraints.biggest;
        if (screen != _screen) {
          _screen = screen;
          _tx = _clampTx(_tx, _scale);
        }
        _measure();
        return Listener(
          onPointerDown: _onPointerDown,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: _onTapUp,
            onDoubleTapDown: (details) => _doubleTapAt = details.localPosition,
            onDoubleTap: _onDoubleTap,
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            onScaleEnd: _onScaleEnd,
            child: ClipRect(child: _buildTransformed()),
          ),
        );
      },
    );
  }

  Widget _buildTransformed() {
    final width = _screen.width;
    final height = _viewportHeight;
    return OverflowBox(
      alignment: Alignment.topLeft,
      minWidth: width,
      maxWidth: width,
      minHeight: height,
      maxHeight: height,
      child: Transform(
        transform: Matrix4.identity()
          ..translateByDouble(_tx, 0, 0, 1)
          ..scaleByDouble(_scale, _scale, 1, 1),
        child: Skeleton(child: _buildScrollView(height)),
      ),
    );
  }

  Widget _buildScrollView(double viewportHeight) {
    final before = _model.before;
    final after = _model.after;
    return CustomScrollView(
      key: ValueKey(_generation),
      controller: _scroll,
      physics: const _ComicScrollPhysics(),
      center: _centerKey,
      // 上下各多排一個螢幕高（Mihon 的 extraLayoutSpace 是四分之三），
      // 捲到之前圖已經在解碼。
      scrollCacheExtent: const ScrollCacheExtent.viewport(1),
      slivers: [
        SliverVariedExtentList(
          itemExtentBuilder: (index, _) =>
              index < before.length ? _extentOf(before[index]) : null,
          delegate: SliverChildBuilderDelegate(
            (context, index) => _buildItem(before[index]),
            childCount: before.length,
            findChildIndexCallback: (key) => _indexByKey(before, key),
          ),
        ),
        SliverVariedExtentList(
          key: _centerKey,
          itemExtentBuilder: (index, _) =>
              index < after.length ? _extentOf(after[index]) : null,
          delegate: SliverChildBuilderDelegate(
            (context, index) => _buildItem(after[index]),
            childCount: after.length,
            findChildIndexCallback: (key) => _indexByKey(after, key),
          ),
        ),
      ],
    );
  }

  static int? _indexByKey(List<ComicStripItem> items, Key key) {
    if (key is! ValueKey<ComicStripItem>) return null;
    final index = items.indexOf(key.value);
    return index < 0 ? null : index;
  }

  Widget _buildItem(ComicStripItem item) {
    final key = ValueKey<ComicStripItem>(item);
    switch (item) {
      case ComicPageItem():
        final url = _model.source.webUrlOf(item.chapterIndex, item.page);
        final opener = widget.webUrlOpener;
        return ComicPageView(
          key: key,
          source: _model.source,
          chapterIndex: item.chapterIndex,
          page: item.page,
          width: _width,
          height: _extentOf(item),
          onAspectRatio: (ratio) => _onAspectRatio(item, ratio),
          onFailed: (failed) => _onPageFailed(item, failed),
          onOpenWeb: url == null || opener == null ? null : () => opener(url),
        );
      case ComicTransitionItem():
        final pending = _model.pendingChapterOf(item);
        return ComicChapterTransition(
          key: key,
          content: _transitionContent(item),
          foreground: widget.foreground,
          accent: widget.accent,
          onRetry: pending == null ? null : () => _model.retry(pending),
        );
      case ComicChapterPlaceholderItem():
        final state = _model.stateOf(item.chapterIndex);
        if (state is ComicChapterFailed) {
          return ComicChapterTransition(
            key: key,
            content: ComicTransitionContent(
              fromTitle: null,
              toTitle: _titleOf(item.chapterIndex),
              status: ComicTransitionFailed(
                ComicLoadError.describe(state.error),
              ),
            ),
            foreground: widget.foreground,
            accent: widget.accent,
            onRetry: () => _model.retry(item.chapterIndex),
          );
        }
        return SkeletonBox(
          key: key,
          width: _width,
          height: _extentOf(item),
          borderRadius: BorderRadius.zero,
        );
    }
  }

  static int _upperBound(List<double> values, double target) {
    var lo = 0;
    var hi = values.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (values[mid] <= target) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  static int _lowerBound(List<double> values, double target) {
    var lo = 0;
    var hi = values.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (values[mid] < target) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }
}

/// 條漫的捲動物理：清單本身不收拖動（手勢由 [ComicStripView] 處理後交給
/// 捲動位置的 `drag`），放開後照 Android 的慣性滑與邊界。
class _ComicScrollPhysics extends ClampingScrollPhysics {
  const _ComicScrollPhysics({super.parent});

  @override
  _ComicScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      _ComicScrollPhysics(parent: buildParent(ancestor));

  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) => false;
}

class _ComicScrollController extends ScrollController {
  _ComicScrollPosition get comicPosition => position as _ComicScrollPosition;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _ComicScrollPosition(
    physics: physics,
    context: context,
    initialPixels: initialScrollOffset,
    keepScrollOffset: keepScrollOffset,
    oldPosition: oldPosition,
    debugLabel: debugLabel,
  );
}

class _ComicScrollPosition extends ScrollPositionWithSingleContext {
  _ComicScrollPosition({
    required super.physics,
    required super.context,
    super.initialPixels,
    super.keepScrollOffset,
    super.oldPosition,
    super.debugLabel,
  });

  /// 上面的內容高度變了 [delta]：捲動位置跟著補，畫面上看到的不動。拖動
  /// 中直接改位置、拖動接著算；慣性滑動中從補過的位置照原本的速度接著滑。
  void shiftBy(double delta) {
    final current = activity;
    if (current is DragScrollActivity) {
      correctBy(delta);
      return;
    }
    final velocity = current is BallisticScrollActivity
        ? current.velocity
        : 0.0;
    jumpTo(pixels + delta);
    if (velocity != 0) goBallistic(velocity);
  }
}
