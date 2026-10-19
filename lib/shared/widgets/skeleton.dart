import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../theme/app_tokens.dart';

import 'cover_reveal.dart';
import 'launch_entrance.dart';
import 'skeleton_reveal.dart';

/// 骨架載入：資料還沒到時，以淡紙色的形狀標出內容將出現的位置（封面方塊、
/// 文字條），取代置中的轉圈。
///
/// [Skeleton] 提供一個共用的呼吸脈動，底下的 [SkeletonBox]／[SkeletonLine]
/// 只改自己的底色，不對整塊做透明度，不需離屏合成。系統要求減少動態
/// （`MediaQuery.disableAnimations`）時保持靜態。
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, required this.child});

  final Widget child;

  /// 佔位形狀的底色：主要文字色疊一層很淡的透明度，淺色是略深一階的紙，
  /// 深色是略亮一階的墨；各風格都從自己的配色推導。
  static Color colorOf(BuildContext context) {
    final theme = Theme.of(context);
    return tint(
      theme.colorScheme.onSurface,
      dark: theme.brightness == Brightness.dark,
    );
  }

  /// [colorOf] 的配色公式，給不從 App 主題取色的畫面（例如閱讀器用自己的
  /// 正文色）共用。
  static Color tint(Color ink, {required bool dark}) =>
      ink.withValues(alpha: dark ? 0.09 : 0.07);

  /// 脈動進度 [pulse]（0 最深、1 最淺）對應的深淺比例，乘在佔位底色的
  /// 透明度上。
  static double pulseStrength(double pulse) => 1 - (1 - _pulseFloor) * pulse;

  /// 脈動最淺時保留的深淺比例：再淺就會在紙上消失，看不出形狀。
  static const double _pulseFloor = 0.55;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.skeletonPulse,
  );
  late final Animation<double> _pulse = CurvedAnimation(
    parent: _controller,
    curve: AppMotion.fadeCurve,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _SkeletonScope(pulse: _pulse, child: widget.child);
}

class _SkeletonScope extends InheritedWidget {
  const _SkeletonScope({required this.pulse, required super.child});

  final Animation<double> pulse;

  static Animation<double>? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SkeletonScope>()?.pulse;

  @override
  bool updateShouldNotify(_SkeletonScope oldWidget) =>
      !identical(pulse, oldWidget.pulse);
}

/// 方塊佔位（封面、按鈕）。放在 [Skeleton] 底下時跟著呼吸。
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height,
    this.borderRadius = AppRadius.cardXs,
    this.color,
  });

  final double? width;
  final double? height;
  final BorderRadius borderRadius;

  /// 佔位底色；null 時取 [Skeleton.colorOf]。不從 App 主題取色的畫面
  /// （例如閱讀器）傳 [Skeleton.tint] 算好的顏色。
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final base = color ?? Skeleton.colorOf(context);
    final pulse = _SkeletonScope.maybeOf(context);
    Widget box(Color color) => SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(color: color, borderRadius: borderRadius),
      ),
    );
    if (pulse == null) return box(base);
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, _) {
        final factor = Skeleton.pulseStrength(pulse.value);
        return box(base.withValues(alpha: base.a * factor));
      },
    );
  }
}

/// 一行文字的佔位：佔用與 [style] 一行文字相同的高度（跟著系統字級
/// 放大），中間畫一條約字身高的圓角條，版面不會在內容出現時跳動。
class SkeletonLine extends StatelessWidget {
  const SkeletonLine({super.key, required this.style, this.widthFactor = 1});

  final TextStyle style;

  /// 佔可用寬度的比例；同一區塊的幾行用不同長度，看起來才像文字。
  final double widthFactor;

  @override
  Widget build(BuildContext context) {
    final fontSize = MediaQuery.textScalerOf(context)
        .scale(style.fontSize ?? 14);
    return SizedBox(
      height: fontSize * (style.height ?? 1.3),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: widthFactor,
          child: SkeletonBox(
            height: fontSize * 0.75,
            borderRadius: AppRadius.cardXs,
          ),
        ),
      ),
    );
  }
}

/// 骨架與真實內容之間的切換：資料到了以骨架換場（[SkeletonReveal]，使用者
/// 在「外觀與主題」選的方式與時長）換成內容；重新載入時骨架也照同樣的方式
/// 與時長長回來。
///
/// 兩者都撐滿父層（呼叫端給的是整頁內容區）。[builder] 只在載入完成後
/// 才呼叫。
class SkeletonSwitcher extends StatefulWidget {
  const SkeletonSwitcher({
    super.key,
    required this.loading,
    required this.skeleton,
    required this.builder,
    this.waitForCovers = false,
    this.entrance,
  });

  final bool loading;
  final Widget skeleton;
  final WidgetBuilder builder;

  /// 資料到了先在骨架底下建好內容，等畫面上的封面解碼好（最多
  /// [AppMotion.revealCoverWait]），再連同封面一次換場；不會先出現空白的
  /// 書卡、封面再一張張浮出來。
  final bool waitForCovers;

  /// 開 App 的進場（書架的骨架，見 [LaunchEntrance]）：骨架照它的進度、以
  /// 骨架換場的方式出現；這段期間資料到了也先不建內容、不換場，播完才接著
  /// 做（ADR 0018）。第一次換成內容時，頁首按鈕與分頁列跟著同一段換場
  /// （[LaunchEntranceMotion.revealWith]）。null 時骨架一開始就在。
  final LaunchEntranceMotion? entrance;

  @override
  State<SkeletonSwitcher> createState() => _SkeletonSwitcherState();
}

class _SkeletonSwitcherState extends State<SkeletonSwitcher>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    value: widget.loading || _entering ? 0 : 1,
  )..addStatusListener((_) => setState(() {}));
  late final Animation<double> _content = CurvedAnimation(
    parent: _controller,
    curve: AppMotion.fadeCurve,
  );
  late final Animation<double> _skeleton = ReverseAnimation(_content);

  /// 這一次換進來的是哪一層：換成內容，或重新載入時長回骨架。
  SkeletonRevealSide _incoming = SkeletonRevealSide.content;

  /// 這一次換場是不是由左而右。
  bool _sweep = false;

  /// 淡入前等封面的那一輪；等完或重新載入就換掉。
  CoverReveal? _reveal;

  /// 重新載入、淡回骨架時，淡出中的內容沿用上一次建好的樣子。
  Widget? _lastContent;

  /// 骨架還在進場：這段期間當作還在載入。
  bool get _entering {
    final entrance = widget.entrance;
    return entrance != null && !entrance.skeleton.isCompleted;
  }

  @override
  void initState() {
    super.initState();
    widget.entrance?.skeleton.addStatusListener(_onEntranceStatus);
    // 一開始就是內容（沒有骨架可換）時，進場的按鈕也直接到位。
    if (_controller.isCompleted) {
      widget.entrance?.revealWith(_content, sweep: false);
    }
  }

  @override
  void didUpdateWidget(SkeletonSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.entrance, oldWidget.entrance)) {
      oldWidget.entrance?.skeleton.removeStatusListener(_onEntranceStatus);
      widget.entrance?.skeleton.addStatusListener(_onEntranceStatus);
    }
    if (widget.loading == oldWidget.loading) return;
    _reveal = null;
    if (widget.loading) {
      _prepare(SkeletonRevealSide.skeleton);
      _controller.reverse();
    } else if (!_entering) {
      _onLoaded(duringBuild: true);
    }
  }

  void _onEntranceStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    setState(() {});
    if (!widget.loading) _onLoaded();
  }

  void _onLoaded({bool duringBuild = false}) {
    if (widget.waitForCovers) {
      final reveal = _reveal = CoverReveal();
      // 淡回骨架途中又載入完成時，新內容也要從全透明開始等。換場進度可能
      // 接著開 App 的頁首按鈕與分頁列（[LaunchEntranceMotion.revealWith]），
      // 建畫面途中歸零會讓它們在別人建構時重建；先停住，這一幀畫完再歸零
      // （封面最快也要下一輪才等完）。
      if (duringBuild) {
        _controller.stop();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && identical(_reveal, reveal)) _controller.value = 0;
        });
      } else {
        _controller.value = 0;
      }
      unawaited(
        reveal.settle(AppMotion.revealCoverWait).whenComplete(() {
          if (mounted && identical(_reveal, reveal)) _revealContent();
        }),
      );
    } else {
      _revealContent();
    }
  }

  void _revealContent() {
    _prepare(SkeletonRevealSide.content);
    widget.entrance?.revealWith(_content, sweep: _sweep);
    _controller.forward();
  }

  /// 這一次換場照使用者選的方式與時長。換場途中反過來時沿用這一輪的方向
  /// 與方式倒著走：換掉 [_incoming] 會讓左右的濃淡在同一幀對調。
  void _prepare(SkeletonRevealSide incoming) {
    final reveal = SkeletonReveal.of(context);
    if (!_controller.isAnimating) {
      _incoming = incoming;
      _sweep = reveal.sweeps;
    }
    _controller
      ..duration = reveal.duration
      ..reverseDuration = reveal.duration;
  }

  @override
  void dispose() {
    widget.entrance?.skeleton.removeStatusListener(_onEntranceStatus);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reveal = _reveal;
    final entrance = _entering ? widget.entrance : null;
    final appearing = entrance?.skeleton;
    final loading = widget.loading || entrance != null;
    final hidden = loading || reveal != null && reveal.waiting;
    Widget? content = _lastContent;
    if (!loading) {
      content = _lastContent = reveal == null
          ? Builder(builder: widget.builder)
          : CoverRevealScope(
              notifier: reveal,
              child: Builder(builder: widget.builder),
            );
    }
    // 兩層各有 key：另一層進出 Stack 時不會被錯配、重建。
    return Stack(
      fit: StackFit.expand,
      children: [
        if (!_controller.isCompleted)
          SkeletonRevealLayer(
            key: const ValueKey('skeleton'),
            opacity: appearing ?? _skeleton,
            side: SkeletonRevealSide.skeleton,
            incoming: entrance == null
                ? _incoming
                : SkeletonRevealSide.skeleton,
            sweep: entrance?.sweep ?? _sweep,
            child: Skeleton(child: widget.skeleton),
          ),
        // 等封面時內容已經建在骨架底下，只是還全透明。
        if (content != null && (!_controller.isDismissed || reveal != null))
          SkeletonRevealLayer(
            key: const ValueKey('content'),
            opacity: _content,
            side: SkeletonRevealSide.content,
            incoming: _incoming,
            sweep: _sweep,
            // 還沒淡入或正在淡出的內容不接點擊、不給讀屏念。
            child: IgnorePointer(
              ignoring: hidden,
              child: ExcludeSemantics(excluding: hidden, child: content),
            ),
          ),
      ],
    );
  }
}

/// 清單（sliver）版的 [SkeletonSwitcher]：載入中是一段 [skeleton]（一般
/// box）；資料到了先把 [builder] 給的 slivers 在骨架底下排好（全透明），
/// 下一幀才照骨架換場（[SkeletonReveal]，使用者選的方式與時長）讓內容淡入、
/// 骨架淡出，兩者疊在同一個位置、跟著捲動。換場只改透明度，結束後骨架
/// 移出畫面、內容不留圖層。系統關閉動畫時直接換成內容。
///
/// 骨架照內容的形狀畫（呼叫端用已知的資料排），換場時版面不跳。換場中
/// 骨架只疊在內容上、不佔捲動範圍，捲動範圍從內容排好那一幀就是內容的。
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
  late final Animation<double> _content = CurvedAnimation(
    parent: _controller,
    curve: AppMotion.fadeCurve,
  );
  late final Animation<double> _skeleton = ReverseAnimation(_content);

  /// 骨架從載入中的 sliver 移到換場時疊在內容上的那一層，呼吸不從頭開始。
  final GlobalKey _skeletonKey = GlobalKey();

  /// 這一次換場是不是由左而右。
  bool _sweep = false;

  void _onStatus(AnimationStatus status) {
    // 換場播完，骨架移出畫面（呼吸跟著停）。
    if (status.isCompleted && mounted) setState(() {});
  }

  @override
  void didUpdateWidget(SliverSkeletonSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.loading == oldWidget.loading) return;
    _controller.value = 0;
    if (widget.loading) return;
    // 這一幀先在骨架底下排好內容；排版不和換場的第一段擠在同一幀
    // （ADR 0018），下一幀才開始淡。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.loading || !_controller.isDismissed) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _controller.value = 1;
        return;
      }
      final reveal = SkeletonReveal.of(context);
      setState(() => _sweep = reveal.sweeps);
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
    key: _skeletonKey,
    opacity: _skeleton,
    side: SkeletonRevealSide.skeleton,
    sweep: _sweep,
    child: ExcludeSemantics(child: Skeleton(child: widget.skeleton)),
  );

  @override
  Widget build(BuildContext context) {
    if (widget.loading) return SliverToBoxAdapter(child: _buildSkeleton());
    final revealing = !_controller.isCompleted;
    // 兩層各有 key：骨架移出時內容不會被錯配、重建。
    return SliverMainAxisGroup(
      slivers: [
        // 先列的 sliver 畫在上面：骨架疊在內容上。
        if (revealing)
          _SliverOverlay(
            key: const ValueKey('skeleton'),
            child: _buildSkeleton(),
          ),
        _SliverRevealLayer(
          key: const ValueKey('content'),
          opacity: _content,
          sweep: _sweep,
          sliver: _SliverRevealScope(
            revealing: revealing,
            child: SliverMainAxisGroup(slivers: widget.builder(context)),
          ),
        ),
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

/// 不佔捲動範圍、疊在後面 sliver 上的一個 box：畫在這個位置原本該在的地方
/// （捲過去的部分移出上緣），不接點擊。只支援往下捲的清單。
class _SliverOverlay extends SingleChildRenderObjectWidget {
  const _SliverOverlay({super.key, required Widget super.child});

  @override
  _RenderSliverOverlay createRenderObject(BuildContext context) =>
      _RenderSliverOverlay();
}

class _RenderSliverOverlay extends RenderSliver
    with RenderObjectWithChildMixin<RenderBox> {
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
    if (child != null) {
      child.layout(constraints.asBoxConstraints(), parentUsesSize: true);
      (child.parentData! as SliverPhysicalParentData).paintOffset = Offset(
        0,
        -constraints.scrollOffset,
      );
    }
    geometry = SliverGeometry(visible: child != null);
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

/// 換場時內容那一層：照 [opacity] 淡入；[sweep] 時左邊先、右邊後
/// （[SkeletonReveal.incomingOpacityAt]）。box 版是 [SkeletonRevealLayer]；
/// 完全不透明時直接畫、不另開圖層。
class _SliverRevealLayer extends SingleChildRenderObjectWidget {
  const _SliverRevealLayer({
    super.key,
    required this.opacity,
    required this.sweep,
    required Widget sliver,
  }) : super(child: sliver);

  final Animation<double> opacity;
  final bool sweep;

  @override
  _RenderSliverRevealLayer createRenderObject(BuildContext context) =>
      _RenderSliverRevealLayer(opacity: opacity, sweep: sweep);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSliverRevealLayer renderObject,
  ) {
    renderObject
      ..opacity = opacity
      ..sweep = sweep;
  }
}

class _RenderSliverRevealLayer extends RenderProxySliver {
  _RenderSliverRevealLayer({required this._opacity, required this._sweep});

  Animation<double> _opacity;
  set opacity(Animation<double> value) {
    if (identical(_opacity, value)) return;
    if (attached) _opacity.removeListener(_onTick);
    _opacity = value;
    if (attached) _opacity.addListener(_onTick);
    _onTick();
  }

  bool _sweep;
  set sweep(bool value) {
    if (_sweep == value) return;
    _sweep = value;
    _onTick();
  }

  final LayerHandle<OpacityLayer> _opacityLayer = LayerHandle<OpacityLayer>();
  final LayerHandle<ShaderMaskLayer> _maskLayer =
      LayerHandle<ShaderMaskLayer>();
  bool _partial = false;

  double _alphaAt(double u) =>
      SkeletonReveal.incomingOpacityAt(_opacity.value, u, sweep: _sweep);
  bool get _fullyOpaque => _alphaAt(0) >= 1 && _alphaAt(1) >= 1;
  bool get _fullyClear => _alphaAt(0) <= 0 && _alphaAt(1) <= 0;

  void _onTick() {
    final partial = !_fullyOpaque && !_fullyClear;
    if (partial != _partial) {
      _partial = partial;
      markNeedsCompositingBitsUpdate();
    }
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _opacity.addListener(_onTick);
    _partial = !_fullyOpaque && !_fullyClear;
  }

  @override
  void detach() {
    _opacity.removeListener(_onTick);
    super.detach();
  }

  @override
  void dispose() {
    _opacityLayer.layer = null;
    _maskLayer.layer = null;
    super.dispose();
  }

  @override
  bool get alwaysNeedsCompositing => child != null && _partial;

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null || !child.geometry!.visible || _fullyClear) {
      _opacityLayer.layer = null;
      _maskLayer.layer = null;
      return;
    }
    if (_fullyOpaque) {
      _opacityLayer.layer = null;
      _maskLayer.layer = null;
      context.paintChild(child, offset);
      return;
    }
    if (!_sweep) {
      _maskLayer.layer = null;
      _opacityLayer.layer = context.pushOpacity(
        offset,
        Color.getAlphaFromOpacity(_alphaAt(0)),
        super.paint,
        oldLayer: _opacityLayer.layer,
      );
      return;
    }
    _opacityLayer.layer = null;
    final stops = SkeletonReveal.sweepStops(_opacity.value);
    final size = Size(constraints.crossAxisExtent, geometry!.paintExtent);
    final shader = LinearGradient(
      colors: [
        for (final (_, content) in stops) Color.fromRGBO(0, 0, 0, content),
      ],
      stops: [for (final (u, _) in stops) u],
    ).createShader(Offset.zero & size);
    final layer = _maskLayer.layer ??= ShaderMaskLayer();
    layer
      ..shader = shader
      ..maskRect = offset & size
      ..blendMode = BlendMode.dstIn;
    context.pushLayer(layer, super.paint, offset);
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
