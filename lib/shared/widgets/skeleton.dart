import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../theme/app_tokens.dart';

import 'cover_reveal.dart';
import 'launch_entrance.dart';
import 'skeleton_reveal.dart';

/// 骨架的深淺，在「外觀與主題 → 骨架深淺」選：佔位底色是文字色疊上這個
/// 透明度。幾組數值是原型上比過的（2026-10-20）；使用者在素色深色的閱讀器
/// 上看不到原本的骨架，選了 [standard]。[faintest] 是原本的值。
enum SkeletonStrength {
  faintest('很淡', light: 0.07, dark: 0.09),
  faint('淡', light: 0.12, dark: 0.15),
  standard('標準', light: 0.16, dark: 0.20),
  strong('深', light: 0.20, dark: 0.25),
  strongest('很深', light: 0.24, dark: 0.30);

  const SkeletonStrength(this.label, {required this.light, required this.dark});

  final String label;
  final double light;

  /// 深色的底與文字色的對比比淺色小，同樣的透明度看起來比較淡，所以深色
  /// 多疊一些。
  final double dark;

  static SkeletonStrength fromStorage(String? name) =>
      values.where((value) => value.name == name).firstOrNull ?? standard;
}

/// 骨架怎麼呼吸，在「外觀與主題 → 骨架呼吸」選。每個位置照同一個節奏由深
/// 變淺再變深（一輪是 [AppMotion.skeletonPulse] 的兩倍）；由左而右時，越往右
/// 越晚開始，畫面最右邊比最左邊晚 [lag] 輪，看起來是一道明暗由左往右走過去。
enum SkeletonBreath {
  /// 整塊同時變深變淺（原本的樣子）。
  whole('整塊一起', lag: 0),

  /// 傳過整個寬度要半輪：同一時間左右兩端剛好一深一淺。
  gentleSweep('由左而右・緩', lag: 0.5),

  /// 傳過整個寬度要一整輪：畫面上看得到完整的一道明暗。
  waveSweep('由左而右・明顯', lag: 1);

  const SkeletonBreath(this.label, {required this.lag});

  final String label;
  final double lag;

  static SkeletonBreath fromStorage(String? name) =>
      values.where((value) => value.name == name).firstOrNull ?? gentleSweep;
}

/// 骨架的深淺與呼吸，掛在主題上；書架、發現、書籍詳情與閱讀器共用。
@immutable
class SkeletonLook extends ThemeExtension<SkeletonLook> {
  const SkeletonLook({
    this.strength = SkeletonStrength.standard,
    this.breath = SkeletonBreath.gentleSweep,
  });

  final SkeletonStrength strength;
  final SkeletonBreath breath;

  static SkeletonLook of(BuildContext context) =>
      Theme.of(context).extension<SkeletonLook>() ?? const SkeletonLook();

  @override
  SkeletonLook copyWith({SkeletonStrength? strength, SkeletonBreath? breath}) =>
      SkeletonLook(
        strength: strength ?? this.strength,
        breath: breath ?? this.breath,
      );

  @override
  SkeletonLook lerp(SkeletonLook? other, double t) =>
      other == null || t < 0.5 ? this : other;

  @override
  bool operator ==(Object other) =>
      other is SkeletonLook &&
      other.strength == strength &&
      other.breath == breath;

  @override
  int get hashCode => Object.hash(strength, breath);
}

/// 骨架載入：資料還沒到時，以淡紙色的形狀標出內容將出現的位置（封面方塊、
/// 文字條），取代置中的轉圈。
///
/// [Skeleton] 提供一個共用的呼吸節奏，底下的 [SkeletonBox]／[SkeletonLine]
/// 只改自己的底色（由左而右呼吸時是沿橫向的漸層），不對整塊做透明度，不需
/// 離屏合成。系統要求減少動態（`MediaQuery.disableAnimations`）時保持靜態。
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, required this.child});

  final Widget child;

  /// 佔位形狀的底色：主要文字色疊上 [SkeletonLook.strength] 的透明度，淺色
  /// 是深一階的紙，深色是亮一階的墨；各風格都從自己的配色推導。
  static Color colorOf(BuildContext context) {
    final theme = Theme.of(context);
    return tint(
      theme.colorScheme.onSurface,
      dark: theme.brightness == Brightness.dark,
      strength: SkeletonLook.of(context).strength,
    );
  }

  /// [colorOf] 的配色公式，給不從 App 主題取色的畫面（例如閱讀器用自己的
  /// 正文色）共用。
  static Color tint(
    Color ink, {
    required bool dark,
    required SkeletonStrength strength,
  }) => ink.withValues(alpha: dark ? strength.dark : strength.light);

  /// 文字骨架的圓角條佔字號的比例。中文字幾乎撐滿整個字號，條和字一樣高，
  /// 換成文字時才不會大一圈（2026-10-20，原本 0.75）。
  static const double barHeightFactor = 1;

  /// 呼吸一輪的進度 [phase]（0 到 1，0 最深、0.5 最淺）在橫向位置 [u]（0
  /// 畫面左緣、1 右緣）的深淺比例，乘在佔位底色的透明度上。
  static double breathAt(double phase, double u, SkeletonBreath breath) {
    final p = (phase - breath.lag * u) % 1;
    final toFaintest = p < 0.5 ? 2 * p : 2 - 2 * p;
    return 1 - (1 - _pulseFloor) * AppMotion.fadeCurve.transform(toFaintest);
  }

  /// [box] 左右兩緣在螢幕上的橫向位置，以 [viewWidth] 為 1：給 [breathAt] 的
  /// 位置。照實際畫在螢幕上的位置算（含換頁的平移與縮放），由左而右呼吸時
  /// 不同方塊、書架與閱讀器才接得上。在 paint 裡呼叫。
  static (double, double) screenSpan(RenderBox box, double viewWidth) => (
    box.localToGlobal(Offset.zero).dx / viewWidth,
    box.localToGlobal(Offset(box.size.width, 0)).dx / viewWidth,
  );

  /// 呼吸最淺時保留的深淺比例：再淺就會在紙上消失，看不出形狀。
  static const double _pulseFloor = 0.55;

  /// 呼吸一輪的時長：由深到淺、再由淺到深各一段 [AppMotion.skeletonPulse]。
  static Duration get breathCycle => AppMotion.skeletonPulse * 2;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Skeleton.breathCycle,
  );
  bool _breathing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _breathing = !MediaQuery.disableAnimationsOf(context);
    if (!_breathing) {
      _controller.value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _SkeletonScope(
    phase: _breathing ? _controller : null,
    child: widget.child,
  );
}

class _SkeletonScope extends InheritedWidget {
  const _SkeletonScope({required this.phase, required super.child});

  /// 呼吸一輪的進度；null 是不呼吸（減少動態）。
  final Animation<double>? phase;

  /// 在 [Skeleton] 底下時回傳 scope 本身（不呼吸時 [phase] 為 null），不在
  /// 底下時回傳 null。
  static _SkeletonScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SkeletonScope>();

  @override
  bool updateShouldNotify(_SkeletonScope oldWidget) =>
      !identical(phase, oldWidget.phase);
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
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: height,
    child: _SkeletonBoxPaint(
      color: color ?? Skeleton.colorOf(context),
      borderRadius: borderRadius,
      phase: _SkeletonScope.maybeOf(context)?.phase,
      breath: SkeletonLook.of(context).breath,
      viewWidth: MediaQuery.sizeOf(context).width,
    ),
  );
}

/// [SkeletonBox] 的圓角方塊：呼吸時每一幀只重畫自己，不重建。由左而右呼吸
/// 時照方塊在畫面上的橫向位置畫成漸層，同一直行的方塊深淺一致。
class _SkeletonBoxPaint extends LeafRenderObjectWidget {
  const _SkeletonBoxPaint({
    required this.color,
    required this.borderRadius,
    required this.phase,
    required this.breath,
    required this.viewWidth,
  });

  final Color color;
  final BorderRadius borderRadius;
  final Animation<double>? phase;
  final SkeletonBreath breath;
  final double viewWidth;

  @override
  _RenderSkeletonBox createRenderObject(BuildContext context) =>
      _RenderSkeletonBox(
        color: color,
        borderRadius: borderRadius,
        phase: phase,
        breath: breath,
        viewWidth: viewWidth,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSkeletonBox renderObject,
  ) {
    renderObject
      ..color = color
      ..borderRadius = borderRadius
      ..phase = phase
      ..breath = breath
      ..viewWidth = viewWidth;
  }
}

class _RenderSkeletonBox extends RenderBox {
  _RenderSkeletonBox({
    required this._color,
    required this._borderRadius,
    required this._phase,
    required this._breath,
    required this._viewWidth,
  });

  Color _color;
  set color(Color value) {
    if (_color == value) return;
    _color = value;
    markNeedsPaint();
  }

  BorderRadius _borderRadius;
  set borderRadius(BorderRadius value) {
    if (_borderRadius == value) return;
    _borderRadius = value;
    markNeedsPaint();
  }

  Animation<double>? _phase;
  set phase(Animation<double>? value) {
    if (identical(_phase, value)) return;
    if (attached) _phase?.removeListener(markNeedsPaint);
    _phase = value;
    if (attached) _phase?.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  SkeletonBreath _breath;
  set breath(SkeletonBreath value) {
    if (_breath == value) return;
    _breath = value;
    markNeedsPaint();
  }

  double _viewWidth;
  set viewWidth(double value) {
    if (_viewWidth == value) return;
    _viewWidth = value;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _phase?.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _phase?.removeListener(markNeedsPaint);
    super.detach();
  }

  // 和原本的 DecoratedBox 一樣取最小的尺寸，由外層的 SizedBox 決定大小。
  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.smallest;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (size.isEmpty) return;
    final rect = offset & size;
    final paint = Paint();
    final phase = _phase;
    if (phase == null) {
      paint.color = _color;
    } else if (_breath.lag == 0 || _viewWidth <= 0) {
      paint.color = _color.withValues(
        alpha: _color.a * Skeleton.breathAt(phase.value, 0, _breath),
      );
    } else {
      // 兩端都換成螢幕座標：換頁途中整頁在平移、縮放，同一個螢幕位置的
      // 骨架才會一樣深。
      final (left, right) = Skeleton.screenSpan(this, _viewWidth);
      final span = right - left;
      // 呼吸沿橫向是平滑的曲線，每 1/32 個畫面寬取一個停點就看不出折角。
      final count = math.max(2, (span.abs() * 32).ceil() + 1);
      paint.shader = ui.Gradient.linear(
        rect.centerLeft,
        rect.centerRight,
        [
          for (var i = 0; i < count; i++)
            _color.withValues(
              alpha:
                  _color.a *
                  Skeleton.breathAt(
                    phase.value,
                    left + span * i / (count - 1),
                    _breath,
                  ),
            ),
        ],
        [for (var i = 0; i < count; i++) i / (count - 1)],
      );
    }
    context.canvas.drawRRect(_borderRadius.toRRect(rect), paint);
  }
}

/// 一行文字的佔位：佔用與 [style] 一行文字相同的高度（跟著系統字級
/// 放大），中間畫一條和字一樣高的圓角條，版面不會在內容出現時跳動。
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
            height: fontSize * Skeleton.barHeightFactor,
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

  /// [_lastContent] 是照哪一個 widget 與哪一輪等封面建的。
  SkeletonSwitcher? _contentFor;
  CoverReveal? _contentReveal;

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
    // 換場開始與結束時只是自己的動畫狀態變了，沿用同一個內容元件，整頁內容
    // 不重建；上層給了新的 [SkeletonSwitcher] 或換了一輪等封面才重新建。原本
    // 每次都包新的 Builder，換場的第一幀與最後一幀都把整個書架重建一次
    // （ADR 0018）。
    if (!loading &&
        (!identical(_contentFor, widget) ||
            !identical(_contentReveal, reveal))) {
      _contentFor = widget;
      _contentReveal = reveal;
      _lastContent = reveal == null
          ? Builder(builder: widget.builder)
          : CoverRevealScope(
              notifier: reveal,
              child: Builder(builder: widget.builder),
            );
    }
    final content = _lastContent;
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
/// box）；資料到了先把 [builder] 給的 slivers 在骨架底下排好（全透明，一幀
/// 建一個），全部建好的下一幀才照骨架換場（[SkeletonReveal]，使用者選的
/// 方式與時長）讓內容淡入、骨架淡出，兩者疊在同一個位置、跟著捲動。換場
/// 只改透明度，結束後骨架移出畫面、內容不留圖層。系統關閉動畫時直接換成
/// 內容。
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
  late final Animation<double> _content = CurvedAnimation(
    parent: _controller,
    curve: AppMotion.fadeCurve,
  );
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
    // 內容在骨架底下一幀建一個 sliver，全部建好下一幀才開始換場：原本一幀
    // 建完整頁內容（書籍詳情在電腦 debug 模式約 50–100ms），骨架的呼吸在那
    // 一幀頓住；建內容也不和換場的第一段擠在同一幀（ADR 0018）。
    _built = 1;
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
    opacity: _skeleton,
    side: SkeletonRevealSide.skeleton,
    sweep: _sweep,
    child: ExcludeSemantics(child: Skeleton(child: widget.skeleton)),
  );

  Widget? _builtContent;
  SliverSkeletonSwitcher? _builtFor;
  int? _builtCount;

  /// [builder] 給的 slivers；同一個 widget 只呼叫一次，一個個加進來時前面
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
            opacity: _content,
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
