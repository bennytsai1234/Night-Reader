import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../theme/app_tokens.dart';

import 'skeleton.dart';
import 'skeleton_reveal.dart';

/// 清單（sliver）版的 [SkeletonSwitcher]：載入中是一段 [skeleton]（一般
/// box）；資料到了那一幀只換上呼叫端給的新骨架（照到了的資料排），下一幀
/// 起把 [builder] 給的 slivers 在骨架底下排好（全透明，一幀建一個），全部
/// 建好的下一幀才照骨架換場（[SkeletonReveal] 的方式與時長）
/// 讓內容淡入、骨架淡出，兩者疊在同一個位置、跟著捲動。換場只改透明度，
/// 結束後骨架移出畫面、內容不留圖層。系統關閉動畫時直接換成內容。
///
/// 骨架照內容的形狀畫（呼叫端用已知的資料排），換場時版面不跳。資料到了
/// 之後骨架只疊在內容上、不佔捲動範圍；內容還沒建完時補一段空白，捲動
/// 範圍至少還是骨架的長度，全部建好後就是內容的。
/// [builder] 只在載入完成後才呼叫；載入完成後再回到載入中時直接換回骨架
/// （目前沒有這種用法）。
class SliverSkeletonSwitcher extends StatefulWidget {
  const SliverSkeletonSwitcher({
    super.key,
    required this.loading,
    required this.skeleton,
    required this.builder,
  });

  final bool loading;
  final Widget skeleton;
  final List<Widget> Function(BuildContext context) builder;

  @override
  State<SliverSkeletonSwitcher> createState() => _SliverSkeletonSwitcherState();
}

class _SliverSkeletonSwitcherState extends State<SliverSkeletonSwitcher>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    value: widget.loading ? 0 : 1,
  )..addStatusListener(_onStatus);

  /// 內容出現的進度（經過的時間比例，曲線由 [SkeletonReveal] 套）。
  late final Animation<double> _content = _controller;
  late final Animation<double> _skeleton = ReverseAnimation(_content);

  /// 這一次換場是不是由左而右。
  bool _sweep = false;

  /// 骨架底下已經建好的內容 sliver 數；null 是全部。
  int? _built;

  /// 這一輪載入完成的序號；重新載入或換下一輪時，排好的下一步作廢。
  int _round = 0;

  /// 骨架在清單裡的位置與高度，建內容期間撐住捲動範圍（[_SliverHold]）。
  final _SkeletonExtent _extent = _SkeletonExtent();

  void _onStatus(AnimationStatus status) {
    // 換場播完，骨架移出畫面（呼吸跟著停）。
    if (status.isCompleted && mounted) setState(() {});
  }

  @override
  void didUpdateWidget(SliverSkeletonSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.loading == oldWidget.loading) return;
    _controller.value = 0;
    final round = ++_round;
    if (widget.loading) {
      _built = null;
      return;
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _built = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && round == _round) _controller.value = 1;
      });
      return;
    }
    // 資料到的這一幀只讓骨架照新資料變形（呼叫端給的 [skeleton]），下一幀
    // 起內容在骨架底下一幀建一個 sliver，全部建好下一幀才開始換場：原本一幀
    // 建完整頁內容（書籍詳情在電腦 debug 模式約 50–100ms），骨架的呼吸在那
    // 一幀頓住；建內容也不和骨架變形、換場的第一段擠在同一幀（ADR 0018）。
    _built = 0;
    _buildNext(round);
  }

  void _buildNext(int round) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || round != _round || widget.loading) return;
      final built = _built;
      if (built != null && built < (_slivers?.length ?? 0)) {
        setState(() => _built = built + 1);
        _buildNext(round);
        return;
      }
      final reveal = SkeletonReveal.of(context);
      setState(() {
        _built = null;
        _sweep = reveal.sweeps;
      });
      _controller.duration = reveal.duration;
      unawaited(_controller.forward());
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildSkeleton() => SkeletonRevealLayer(
    presence: _skeleton,
    side: SkeletonRevealSide.skeleton,
    sweep: _sweep,
    child: ExcludeSemantics(child: Skeleton(child: widget.skeleton)),
  );

  Widget? _builtContent;
  SliverSkeletonSwitcher? _builtFor;
  int? _builtCount;

  /// [SliverSkeletonSwitcher.builder] 給的 slivers；同一個 widget 只呼叫一次，一個個加進來時前面
  /// 已經建好的沿用同一個 widget，不再重建。
  List<Widget>? _slivers;

  /// 換場開始與結束時只是自己的動畫狀態變了，沿用同一份內容，整頁不重建；
  /// 上層給了新的 [SliverSkeletonSwitcher] 才重新建（ADR 0018）。
  Widget _contentFor(SliverSkeletonSwitcher widget) {
    final count = _built;
    if (!identical(_builtFor, widget)) {
      _builtFor = widget;
      _slivers = null;
    } else if (_builtCount == count && _builtContent != null) {
      return _builtContent!;
    }
    _builtCount = count;
    _builtContent = Builder(
      builder: (context) {
        final slivers = _slivers ??= widget.builder(context);
        return SliverMainAxisGroup(
          slivers: count == null || count >= slivers.length
              ? slivers
              : slivers.sublist(0, count),
        );
      },
    );
    return _builtContent!;
  }

  @override
  Widget build(BuildContext context) {
    final loading = widget.loading;
    final revealing = !loading && !_controller.isCompleted;
    // 兩層各有 key：骨架移出時內容不會被錯配、重建。骨架從載入中到換場一直
    // 是同一個 sliver，只從佔位改成疊在內容上：原本載入中與換場時包在不同
    // 的 sliver 裡，內容到的那一幀整個骨架被搬過去、全部重建，和建內容擠
    // 在同一幀（ADR 0018）。
    final building = !loading && _built != null;
    return SliverMainAxisGroup(
      slivers: [
        // 先列的 sliver 畫在上面：骨架疊在內容上。
        if (loading || revealing)
          _SliverOverlay(
            key: const ValueKey('skeleton'),
            takesSpace: loading,
            extent: _extent,
            child: _buildSkeleton(),
          ),
        if (!loading)
          _SliverRevealLayer(
            key: const ValueKey('content'),
            presence: _content,
            sweep: _sweep,
            // 還在一個個建的內容全透明，不接點擊。
            sliver: SliverIgnorePointer(
              ignoring: building,
              sliver: _SliverRevealScope(
                revealing: revealing,
                child: _contentFor(widget),
              ),
            ),
          ),
        // 內容還沒建完時撐住骨架原本的捲動範圍：已經往下捲的骨架不會因為
        // 內容暫時比較短而被拉回去。
        if (building) _SliverHold(key: const ValueKey('hold'), extent: _extent),
      ],
    );
  }
}

/// 內容是不是跟著 [SliverSkeletonSwitcher] 的換場一起出現：是的話裡面的
/// [SliverFadeIn] 不另外淡一次。
class _SliverRevealScope extends InheritedWidget {
  const _SliverRevealScope({required this.revealing, required super.child});

  final bool revealing;

  static bool of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_SliverRevealScope>()?.revealing ??
      false;

  @override
  bool updateShouldNotify(_SliverRevealScope oldWidget) => false;
}

/// 清單裡的一個 box，畫在這個位置原本該在的地方（捲過去的部分移出上緣），
/// 不接點擊。[takesSpace] 時和 [SliverToBoxAdapter] 一樣佔捲動範圍；否則
/// 不佔、疊在後面的 sliver 上。只支援往下捲的清單。
class _SliverOverlay extends SingleChildRenderObjectWidget {
  const _SliverOverlay({
    super.key,
    required this.takesSpace,
    required this.extent,
    required Widget super.child,
  });

  final bool takesSpace;

  /// 每次排版記下這個 box 在清單裡的位置與高度。
  final _SkeletonExtent extent;

  @override
  _RenderSliverOverlay createRenderObject(BuildContext context) =>
      _RenderSliverOverlay(takesSpace, extent);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSliverOverlay renderObject,
  ) {
    renderObject
      ..takesSpace = takesSpace
      ..extent = extent;
  }
}

/// 骨架在清單裡從哪裡開始（前面 sliver 的捲動範圍）、有多高。
class _SkeletonExtent {
  double top = 0;
  double height = 0;
}

class _RenderSliverOverlay extends RenderSliver
    with RenderObjectWithChildMixin<RenderBox> {
  _RenderSliverOverlay(this._takesSpace, this.extent);

  _SkeletonExtent extent;

  bool _takesSpace;
  set takesSpace(bool value) {
    if (_takesSpace == value) return;
    _takesSpace = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! SliverPhysicalParentData) {
      child.parentData = SliverPhysicalParentData();
    }
  }

  @override
  void performLayout() {
    assert(constraints.axisDirection == AxisDirection.down);
    final child = this.child;
    if (child == null) {
      geometry = SliverGeometry.zero;
      return;
    }
    child.layout(constraints.asBoxConstraints(), parentUsesSize: true);
    (child.parentData! as SliverPhysicalParentData).paintOffset = Offset(
      0,
      -constraints.scrollOffset,
    );
    final height = child.size.height;
    extent
      ..top = constraints.precedingScrollExtent
      ..height = height;
    if (!_takesSpace) {
      geometry = const SliverGeometry(visible: true);
      return;
    }
    final painted = calculatePaintOffset(constraints, from: 0, to: height);
    geometry = SliverGeometry(
      scrollExtent: height,
      paintExtent: painted,
      cacheExtent: calculateCacheOffset(constraints, from: 0, to: height),
      maxPaintExtent: height,
      hitTestExtent: painted,
      hasVisualOverflow:
          height > constraints.remainingPaintExtent ||
          constraints.scrollOffset > 0,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    final data = child.parentData! as SliverPhysicalParentData;
    context.paintChild(child, offset + data.paintOffset);
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    (child.parentData! as SliverPhysicalParentData).applyPaintTransform(
      transform,
    );
  }

  @override
  bool hitTest(
    SliverHitTestResult result, {
    required double mainAxisPosition,
    required double crossAxisPosition,
  }) => false;
}

/// 空白的捲動範圍，把前面的 sliver 補到 [extent] 記下的骨架底端；前面已經
/// 比骨架長時不佔位置。放在同一個 [SliverMainAxisGroup] 裡、骨架之後。
class _SliverHold extends LeafRenderObjectWidget {
  const _SliverHold({super.key, required this.extent});

  final _SkeletonExtent extent;

  @override
  _RenderSliverHold createRenderObject(BuildContext context) =>
      _RenderSliverHold(extent);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSliverHold renderObject,
  ) {
    renderObject.extent = extent;
  }
}

class _RenderSliverHold extends RenderSliver {
  _RenderSliverHold(this.extent);

  _SkeletonExtent extent;

  @override
  void performLayout() {
    final gap = math.max(
      0.0,
      extent.top + extent.height - constraints.precedingScrollExtent,
    );
    final painted = calculatePaintOffset(constraints, from: 0, to: gap);
    geometry = SliverGeometry(
      scrollExtent: gap,
      paintExtent: painted,
      cacheExtent: calculateCacheOffset(constraints, from: 0, to: gap),
      maxPaintExtent: gap,
    );
  }
}

/// 換場時內容那一層：照 [presence]（經過的時間比例，同 [SkeletonRevealLayer]）淡入；[sweep] 時左邊先、右邊後
/// （[SkeletonReveal.incomingOpacityAt]）。box 版是 [SkeletonRevealLayer]；
/// 完全不透明時直接畫、不另開圖層。
class _SliverRevealLayer extends SingleChildRenderObjectWidget {
  const _SliverRevealLayer({
    super.key,
    required this.presence,
    required this.sweep,
    required Widget sliver,
  }) : super(child: sliver);

  final Animation<double> presence;
  final bool sweep;

  @override
  _RenderSliverRevealLayer createRenderObject(BuildContext context) =>
      _RenderSliverRevealLayer(presence: presence, sweep: sweep);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSliverRevealLayer renderObject,
  ) {
    renderObject
      ..presence = presence
      ..sweep = sweep;
  }
}

class _RenderSliverRevealLayer extends RenderProxySliver
    with SkeletonRevealPainting {
  _RenderSliverRevealLayer({required this._presence, required this._sweep});

  Animation<double> _presence;
  set presence(Animation<double> value) {
    if (identical(_presence, value)) return;
    if (attached) _presence.removeListener(revealChanged);
    _presence = value;
    if (attached) _presence.addListener(revealChanged);
    revealChanged();
  }

  bool _sweep;
  set sweep(bool value) {
    if (_sweep == value) return;
    _sweep = value;
    revealChanged();
  }

  @override
  double get revealProgress => _presence.value;

  @override
  bool get revealSweep => _sweep;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _presence.addListener(revealChanged);
    syncRevealPartial();
  }

  @override
  void detach() {
    _presence.removeListener(revealChanged);
    super.detach();
  }

  @override
  bool get alwaysNeedsCompositing => child != null && revealPartial;

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null || !child.geometry!.visible) {
      clearRevealLayers();
      return;
    }
    paintRevealed(
      context,
      offset,
      Size(constraints.crossAxisExtent, geometry!.paintExtent),
      super.paint,
    );
  }
}

/// 清單（sliver）區塊第一次出現時以 [AppMotion.fade] 淡入，之後重建不再
/// 播放。跟著 [SliverSkeletonSwitcher] 的換場一起出現的不另外淡（換場已經
/// 讓它淡入），載入完成後才出現的（例如目錄搜尋沒有結果的提示）才淡。
class SliverFadeIn extends StatefulWidget {
  const SliverFadeIn({super.key, required this.sliver});

  final Widget sliver;

  @override
  State<SliverFadeIn> createState() => _SliverFadeInState();
}

class _SliverFadeInState extends State<SliverFadeIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.fade,
  );
  late final Animation<double> _opacity = CurvedAnimation(
    parent: _controller,
    curve: AppMotion.fadeCurve,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller.isAnimating || _controller.isCompleted) return;
    if (MediaQuery.disableAnimationsOf(context) ||
        _SliverRevealScope.of(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      SliverFadeTransition(opacity: _opacity, sliver: widget.sliver);
}
