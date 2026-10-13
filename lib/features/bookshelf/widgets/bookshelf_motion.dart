import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';

/// 書架清單的版面動畫：換排序、或書因閱讀移到最前面時，書卡從舊位置平滑
/// 移到新位置；新加入的書淡入；移出的書直接消失，其他書卡移過去補位。
///
/// 做法是 FLIP：書的順序或成員一改變，就在重建前記下每張書卡（以 bookUrl
/// 辨識）上一幀在螢幕上的位置；新版面排好後，每張書卡在繪製時算出新舊位置
/// 的差，先畫在舊位置，再隨動畫把位移收回零。只改繪製位移與透明度，不觸發
/// 重新排版。
///
/// 網格與列表互換時不播（那是整頁交叉淡化）；拖曳排序放下時清單本身已經
/// 把書卡移到定位，用 [accept] 採用新順序，不再播一次。
class BookshelfLayoutMotion {
  BookshelfLayoutMotion({required TickerProvider vsync})
    : _controller = AnimationController(
        vsync: vsync,
        duration: AppMotion.spring,
      ) {
    _controller
      ..addListener(_repaintAnimated)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _finish();
      });
  }

  final AnimationController _controller;
  final Set<_RenderBookshelfMotionItem> _items = {};

  /// 這一輪開始前每張書卡在螢幕上的位置。
  Map<String, Offset> _before = const {};

  /// 每開始一輪加一；書卡據此判斷是否已經算過這一輪的起點。
  int _generation = 0;

  List<String>? _lastUrls;
  bool? _lastGrid;

  /// 淡入比移動短（[AppMotion.fade] 對 [AppMotion.spring]），在移動的前段完成。
  static final Curve _fadeCurve = Interval(
    0,
    AppMotion.fade.inMicroseconds / AppMotion.spring.inMicroseconds,
    curve: AppMotion.fadeCurve,
  );

  bool get _running => _controller.isAnimating;

  /// 位移還剩下的比例：1 是在舊位置，0 是到定位。
  double get _remaining =>
      _running ? 1 - AppMotion.springCurve.transform(_controller.value) : 0;

  double get _fadeOpacity =>
      _running ? _fadeCurve.transform(_controller.value) : 1;

  /// 建構書架清單時呼叫，傳入目前的書（bookUrl）順序。
  ///
  /// 順序或成員和上次不同、檢視模式相同、[animate] 為 true 時開始一輪動畫。
  /// 第一次載入（上次沒有書）不播，免得一開 App 整片書淡入。
  void update(List<String> urls, {required bool grid, required bool animate}) {
    final previous = _lastUrls;
    final previousGrid = _lastGrid;
    _lastUrls = urls;
    _lastGrid = grid;
    if (!animate || previousGrid != grid) {
      // 換檢視或關掉動畫時，進行中這一輪的起點已經不適用：停在終點，
      // 不讓新檢視的書卡從舊檢視的位置飛過來。
      _stop();
      return;
    }
    if (previous == null || previous.isEmpty || listEquals(previous, urls)) {
      return;
    }
    final before = <String, Offset>{};
    for (final item in _items) {
      final position = item._visualPosition();
      if (position != null) before[item.id] = position;
      // 書卡可能只是換了位置、內容沒變，不重畫就算不到新位置。
      item.markNeedsPaint();
    }
    _before = before;
    _generation++;
    _controller.forward(from: 0);
  }

  /// 清單已經自己把書卡移到新順序（拖曳排序放下）：記下新順序，不播動畫。
  void accept(List<String> urls) => _lastUrls = urls;

  void _repaintAnimated() {
    for (final item in _items) {
      if (item._animated) item.markNeedsPaint();
    }
  }

  void _finish() {
    _before = const {};
    for (final item in _items) {
      if (item._animated) item.markNeedsPaint();
    }
  }

  void _stop() {
    if (!_running) return;
    _controller.stop();
    _finish();
  }

  void dispose() => _controller.dispose();
}

/// 書架上的一張書卡；[id] 是書的 bookUrl。
class BookshelfMotionItem extends StatelessWidget {
  const BookshelfMotionItem({
    super.key,
    required this.id,
    required this.motion,
    required this.child,
  });

  final String id;
  final BookshelfLayoutMotion motion;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // 書卡自成一個繪製層：移動時只改這一層的位置，不重畫書卡內容。
    return _BookshelfMotionBox(
      id: id,
      motion: motion,
      child: RepaintBoundary(child: child),
    );
  }
}

class _BookshelfMotionBox extends SingleChildRenderObjectWidget {
  const _BookshelfMotionBox({
    required this.id,
    required this.motion,
    required super.child,
  });

  final String id;
  final BookshelfLayoutMotion motion;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderBookshelfMotionItem(motion, id: id);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderBookshelfMotionItem renderObject,
  ) {
    renderObject
      ..id = id
      ..motion = motion;
  }
}

class _RenderBookshelfMotionItem extends RenderProxyBox {
  _RenderBookshelfMotionItem(this._motion, {required this.id});

  String id;

  BookshelfLayoutMotion get motion => _motion;
  BookshelfLayoutMotion _motion;
  set motion(BookshelfLayoutMotion value) {
    if (identical(value, _motion)) return;
    if (attached) {
      _motion._items.remove(this);
      value._items.add(this);
    }
    _motion = value;
  }

  /// 已經算過起點的那一輪；新建的書卡從 0 開始，第一次繪製時就會算。
  int _resolvedGeneration = 0;

  /// 這一輪開始時從新位置指回舊位置的位移；null 表示不移動。
  Offset? _from;

  /// 這一輪是否淡入（新加入，或原本不在畫面上）。
  bool _fadeIn = false;

  bool get _animated => _from != null || _fadeIn;

  Offset get _shift {
    final from = _from;
    return from == null ? Offset.zero : from * motion._remaining;
  }

  double get _opacity => _fadeIn ? motion._fadeOpacity : 1;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    motion._items.add(this);
  }

  @override
  void detach() {
    motion._items.remove(this);
    super.detach();
  }

  /// 目前畫在螢幕上的位置（含這一輪尚未收回的位移）。
  Offset? _visualPosition() {
    if (!attached || !hasSize) return null;
    return localToGlobal(Offset.zero) + _shift;
  }

  /// 第一次在這一輪繪製時，比對新舊位置決定怎麼動。
  void _resolve() {
    if (_resolvedGeneration == motion._generation) return;
    _resolvedGeneration = motion._generation;
    _from = null;
    _fadeIn = false;
    if (!motion._running) return;
    final before = motion._before[id];
    if (before == null) {
      _fadeIn = true;
      return;
    }
    final delta = before - localToGlobal(Offset.zero);
    // 不到半個像素的差是捲動或取整造成的，不算移動。
    if (delta.distance >= 0.5) _from = delta;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    _resolve();
    if (!motion._running) {
      _from = null;
      _fadeIn = false;
    }
    final shifted = offset + _shift;
    final alpha = (_opacity * 255).round();
    if (alpha >= 255) {
      layer = null;
      context.paintChild(child, shifted);
      return;
    }
    layer = context.pushOpacity(
      shifted,
      alpha,
      (context, offset) => context.paintChild(child, offset),
      oldLayer: layer as OpacityLayer?,
    );
  }

  /// 換位中的書卡不接點擊：清單依版面位置分派點擊，畫在別格的書卡收不到
  /// 自己的點擊，點它所在的格子反而會點到排在那裡的另一本書。換位只有
  /// [AppMotion.spring] 這麼久，停住點擊比點錯書好。
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (_from != null && motion._running) return false;
    return super.hitTest(result, position: position);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null) return false;
    return result.addWithPaintOffset(
      offset: _shift,
      position: position,
      hitTest: (result, transformed) =>
          child.hitTest(result, position: transformed),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final shift = _shift;
    transform.translateByDouble(shift.dx, shift.dy, 0, 1);
  }
}
