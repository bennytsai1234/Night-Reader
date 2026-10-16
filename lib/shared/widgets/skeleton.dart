import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

import 'package:night_reader/core/services/motion_gate.dart';

import 'cover_reveal.dart';

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

  /// 畫面上看得到的骨架在呼吸時持有 [MotionGate]（ADR 0018）；被別的頁面
  /// 蓋住（TickerMode 關掉）時放開。
  final MotionHold _hold = MotionHold();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
    _hold.moving =
        _controller.isAnimating && TickerMode.valuesOf(context).enabled;
  }

  @override
  void dispose() {
    _hold.release();
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

/// 骨架與真實內容之間的切換：資料到了以 [AppMotion.fade] 淡入取代骨架。
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
  });

  final bool loading;
  final Widget skeleton;
  final WidgetBuilder builder;

  /// 資料到了先在骨架底下建好內容，等畫面上的封面解碼好（最多
  /// [AppMotion.revealCoverWait]），再以 [AppMotion.reveal] 連同封面一次
  /// 淡入；不會先出現空白的書卡、封面再一張張浮出來。
  final bool waitForCovers;

  @override
  State<SkeletonSwitcher> createState() => _SkeletonSwitcherState();
}

class _SkeletonSwitcherState extends State<SkeletonSwitcher>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.waitForCovers ? AppMotion.reveal : AppMotion.fade,
    value: widget.loading ? 0 : 1,
  )..addStatusListener((_) => setState(() {}));
  late final Animation<double> _content = CurvedAnimation(
    parent: _controller,
    curve: AppMotion.fadeCurve,
  );
  late final Animation<double> _skeleton = ReverseAnimation(_content);

  /// 淡入前等封面的那一輪；等完或重新載入就換掉。
  CoverReveal? _reveal;

  /// 重新載入、淡回骨架時，淡出中的內容沿用上一次建好的樣子。
  Widget? _lastContent;

  @override
  void didUpdateWidget(SkeletonSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.loading == oldWidget.loading) return;
    _reveal = null;
    if (widget.loading) {
      _controller.reverse();
    } else if (widget.waitForCovers) {
      final reveal = _reveal = CoverReveal();
      unawaited(
        reveal.settle(AppMotion.revealCoverWait).whenComplete(() {
          if (mounted && identical(_reveal, reveal)) _controller.forward();
        }),
      );
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
  Widget build(BuildContext context) {
    final reveal = _reveal;
    final hidden = widget.loading || reveal != null && reveal.waiting;
    Widget? content = _lastContent;
    if (!widget.loading) {
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
          FadeTransition(
            key: const ValueKey('skeleton'),
            opacity: _skeleton,
            child: Skeleton(child: widget.skeleton),
          ),
        // 等封面時內容已經建在骨架底下，只是還全透明。
        if (content != null && (!_controller.isDismissed || reveal != null))
          FadeTransition(
            key: const ValueKey('content'),
            opacity: _content,
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

/// 清單（sliver）版的淡入：骨架換成真實內容時，內容以 [AppMotion.fade]
/// 淡入。只在第一次出現時淡入一次，之後重建不再播放。
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
    if (MediaQuery.disableAnimationsOf(context)) {
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
