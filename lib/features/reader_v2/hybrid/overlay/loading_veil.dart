import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';
import 'package:night_reader/shared/widgets/skeleton_reveal.dart';

/// 開書、跳章與重新排版時蓋在正文上的一張紙。
///
/// 排版期間整張紙蓋住，接在開書轉場後面看起來是同一張紙。跳章、改排版與
/// 重載內容時舊正文還在畫面上，紙以 [AppMotion.fade] 淡入蓋過它
/// （[cover] 的 `fade`），蓋滿（[covered]）才拿掉舊正文、開始排版
/// （ADR 0018）。紙上的骨架照
/// 一頁真正的每一行畫：開書有上次記下的那一頁時紙一蓋上就淡入，其他時候
/// 紙先空著，第一頁排好後才照它淡入（[showSkeleton]，ADR 0016、0024）。
/// 骨架出現與正文排好後掀紙都照骨架換場（[SkeletonReveal] 的方式與時長）：骨架照它長出來，掀紙時骨架跟著紙一起淡掉、露出正文。
///
/// 只改紙與骨架顏色的透明度，不對正文做整頁 Opacity：載入期間排版用滿每
/// 一幀的預算，這一層每幀只多畫幾十個圓角條。
class LoadingVeilController {
  /// 紙上骨架的呼吸照 [breath] 走，和頁首頁尾的骨架同一口
  /// （[SharedSkeletonBreathScope]）；沒給時自己一口。
  LoadingVeilController({
    required TickerProvider vsync,
    SharedSkeletonBreath? breath,
    this.onHidden,
  }) : _cover = AnimationController(
         vsync: vsync,
         duration: AppMotion.fade,
         value: 1,
       ),
       _skeleton = AnimationController(
         vsync: vsync,
         duration: AppMotion.fade,
         reverseDuration: AppMotion.fade,
       ),
       _ownsBreath = breath == null,
       _breath = breath ?? SharedSkeletonBreath(vsync: vsync) {
    _cover.addStatusListener(_onCoverStatus);
    _skeleton.addStatusListener(_onSkeletonStatus);
  }

  /// 紙完全淡出時呼叫，呼叫端據此把 [LoadingVeil] 移出畫面。
  final VoidCallback? onHidden;

  /// 這一次掀紙是不是由左而右。
  bool _sweep = false;

  /// 骨架出現的方式與時長，見 [skeletonReveal]。
  SkeletonReveal _skeletonReveal = const SkeletonReveal();

  /// 這一次骨架出現是不是由左而右；骨架自己淡掉時一律整頁淡。
  bool _skeletonSweep = false;

  final AnimationController _cover;
  final AnimationController _skeleton;
  final SharedSkeletonBreath _breath;
  final bool _ownsBreath;

  /// 紙上的骨架正在用 [_breath]（登記成它的使用者）。
  bool _usingBreath = false;
  int _attachedVeils = 0;
  bool _reduceMotion = false;

  /// 系統要求減少動態（`MediaQuery.disableAnimations`）時，紙與骨架直接到位，
  /// 骨架不呼吸；中途切換時，進行中的淡出與淡入也直接跳到終點（淡入中的
  /// 紙蓋滿、掀開中的紙掀掉）。
  set reduceMotion(bool value) {
    if (_reduceMotion == value) return;
    _reduceMotion = value;
    if (value) {
      if (_cover.isAnimating) {
        _cover.value = _cover.status == AnimationStatus.forward ? 1 : 0;
      }
      if (_skeleton.isAnimating) {
        _skeleton.value = _skeleton.status == AnimationStatus.reverse ? 0 : 1;
      }
    }
    _syncPulse();
  }

  /// 骨架出現照的骨架換場設定，呼叫端從主題取得、設定改變時更新。開書時
  /// 骨架在拿到主題之前就開始出現，這時改照新的方式與時長走完剩下的部分。
  set skeletonReveal(SkeletonReveal value) {
    if (_skeletonReveal == value) return;
    _skeletonReveal = value;
    if (_skeleton.status == AnimationStatus.forward) {
      _skeletonSweep = value.sweeps;
      _skeleton.duration = value.duration;
      unawaited(_skeleton.forward());
    }
  }

  /// 紙還蓋著或正在淡入、淡出。
  bool get isVisible => !_cover.isDismissed;

  /// 紙整張蓋滿、沒有在淡入淡出。
  bool get isCovered => _cover.isCompleted;

  /// 紙正在掀開（淡出中）。
  bool get isRevealing => _cover.status == AnimationStatus.reverse;

  /// 等 [covered] 的呼叫端；紙不再往蓋滿走（蓋滿、改成掀開）或控制器
  /// 拆掉時，每一個都完成一次。
  final List<Completer<bool>> _coverWaiters = <Completer<bool>>[];

  /// 淡入停下來時完成：整張蓋滿為 true；途中改成掀開、或控制器拆掉時為
  /// false，呼叫端當成這次蓋紙取消。沒有在淡入時立即以目前是否蓋滿完成。
  Future<bool> get covered {
    if (_cover.status != AnimationStatus.forward) {
      return Future<bool>.value(_cover.isCompleted);
    }
    final waiter = Completer<bool>();
    _coverWaiters.add(waiter);
    return waiter.future;
  }

  void _settleCoverWaiters({required bool covered}) {
    if (_coverWaiters.isEmpty) return;
    final waiters = List<Completer<bool>>.of(_coverWaiters);
    _coverWaiters.clear();
    for (final waiter in waiters) {
      waiter.complete(covered);
    }
  }

  /// 骨架還在淡入或淡出。
  bool get isSkeletonFading => _skeleton.isAnimating;

  /// 紙上還看得到骨架（含淡出中）。
  bool get hasSkeleton => !_skeleton.isDismissed;

  /// 蓋上整張紙。[skeleton] 為 true 時骨架從目前的濃淡繼續淡入（淡出途中
  /// 再蓋上不會先閃空）；false 時紙先空著，等 [showSkeleton]，已經畫著的
  /// 骨架淡掉。
  ///
  /// [fade] 時紙從目前的濃淡以 [AppMotion.fade] 淡入（底下的舊正文還在，
  /// 等 [covered] 再拿掉）；否則直接蓋滿。掀紙途中再淡入時沿用那次掀紙的
  /// 方式倒回來，其他時候整張一起淡。
  void cover({bool skeleton = true, bool fade = false}) {
    _settling = false;
    if (fade && !_reduceMotion) {
      if (!_cover.isAnimating) _sweep = false;
      unawaited(_cover.forward());
    } else {
      _cover.value = 1;
    }
    if (skeleton) {
      showSkeleton();
    } else {
      hideSkeleton();
    }
  }

  /// 照 [skeletonReveal] 讓紙上的骨架出現。要長出的新骨架不呼吸（ADR
  /// 0025）：上一輪還在呼吸（呼吸中又跳章、改排版或重載）就讓這一口自然
  /// 呼完、停在最深，頁首頁尾的骨架一起收，長完再從最深算
  /// [restBeforeBreath]。
  void showSkeleton() {
    if (_reduceMotion) {
      _skeleton.value = 1;
    } else {
      if (!_skeleton.isCompleted) unawaited(_breath.settle());
      _skeletonSweep = _skeletonReveal.sweeps;
      _skeleton.duration = _skeletonReveal.duration;
      unawaited(_skeleton.forward());
    }
    _syncPulse();
    // 骨架本來就長好了（又蓋一次紙）：不會再有長完的那一刻，從現在算起。
    if (_skeleton.isCompleted) _waitThenBreathe();
  }

  /// 淡掉紙上的骨架，紙留著，之後會長出新的一份（[showSkeleton]）：還在
  /// 呼吸就從現在起收住，淡掉的同時把這一口呼完，新骨架長出時已經靜止。
  void hideSkeleton() {
    if (!_reduceMotion) unawaited(_breath.settle());
    _skeletonSweep = false;
    if (_reduceMotion || _skeleton.isDismissed) {
      _skeleton.value = 0;
    } else {
      unawaited(_skeleton.reverse());
    }
    _syncPulse();
  }

  /// 骨架長完後停在最深等正文的時間：這段時間裡排好就不呼吸，直接建正文、
  /// 掀紙；超過才開始呼吸。讀過的書多半在這之內排好（2026-11-08 電腦上量
  /// 約 0.37 秒），要上網抓的也不會讓骨架靜止太久、看起來像當掉。
  static const Duration restBeforeBreath = Duration(milliseconds: 500);

  Timer? _breathTimer;

  /// 骨架長完：先停在最深 [restBeforeBreath]，正文還沒排好才開始呼吸。
  void _waitThenBreathe() {
    _breathTimer?.cancel();
    if (_settling) return;
    _breathTimer = Timer(restBeforeBreath, () {
      _breathTimer = null;
      if (!_settling && _skeleton.isCompleted) _breath.begin();
    });
  }

  /// 正文排好、要掀紙前收住骨架的呼吸，和開 App 換場前一樣（ADR 0035）：
  /// 骨架還在長出、或長完後還在停著（[restBeforeBreath]）時不開始呼吸，
  /// 等長完就完成；已經在呼吸時等每個位置把這一口呼完、停在最深。全部
  /// 靜止時完成，之後才在紙底下建正文，掀紙時骨架不再呼吸（ADR 0037
  /// 策略一、二）。收的是共用的那口呼吸，頁首頁尾的骨架一起收。
  Future<void> settleBreath() async {
    _settling = true;
    _breathTimer?.cancel();
    _breathTimer = null;
    await _grown;
    if (_disposed) return;
    await _breath.settle();
  }

  /// 骨架不再往長完走（長完、改成淡掉、或控制器拆掉）時完成。
  Future<void> get _grown {
    if (_disposed || _skeleton.status != AnimationStatus.forward) {
      return Future<void>.value();
    }
    final waiter = Completer<void>();
    _grownWaiters.add(waiter);
    return waiter.future;
  }

  final List<Completer<void>> _grownWaiters = <Completer<void>>[];

  void _settleGrownWaiters() {
    if (_grownWaiters.isEmpty) return;
    final waiters = List<Completer<void>>.of(_grownWaiters);
    _grownWaiters.clear();
    for (final waiter in waiters) {
      waiter.complete();
    }
  }

  bool _disposed = false;

  /// 這次掀紙作廢、紙還要再等：骨架已經長完就從現在起停 [restBeforeBreath]
  /// 再呼吸（收住途中時等這一口呼完再起），還在長的等長完才算。
  void resumeBreath() {
    _settling = false;
    if (_skeleton.isCompleted) _waitThenBreathe();
  }

  /// 正文排好、在等收住（[settleBreath]）：骨架長完時不開始呼吸。
  bool _settling = false;

  /// 正文已排好：照 [reveal] 的方式與時長掀開紙。
  void reveal([SkeletonReveal reveal = const SkeletonReveal()]) {
    if (_reduceMotion) {
      _cover.value = 0;
    } else {
      _sweep = reveal.sweeps;
      _cover.reverseDuration = reveal.duration;
      unawaited(_cover.reverse());
    }
  }

  void dispose() {
    _disposed = true;
    _breathTimer?.cancel();
    _settleGrownWaiters();
    _cover.removeStatusListener(_onCoverStatus);
    _skeleton.removeStatusListener(_onSkeletonStatus);
    _settleCoverWaiters(covered: false);
    _setUsingBreath(false);
    _cover.dispose();
    _skeleton.dispose();
    if (_ownsBreath) _breath.dispose();
  }

  void _onCoverStatus(AnimationStatus status) {
    if (status != AnimationStatus.forward) {
      _settleCoverWaiters(covered: status == AnimationStatus.completed);
    }
    if (status != AnimationStatus.dismissed) return;
    _skeleton.value = 0;
    _syncPulse();
    onHidden?.call();
  }

  /// 骨架長完、停在最深（和開 App 一樣，長出時不呼吸，ADR 0025、0035）：
  /// 正文在 [restBeforeBreath] 內排好就不呼吸、直接收住掀紙，沒好才開始
  /// 呼吸。
  void _onSkeletonStatus(AnimationStatus status) {
    if (status != AnimationStatus.forward) _settleGrownWaiters();
    if (status == AnimationStatus.completed) _waitThenBreathe();
  }

  void _attach() {
    _attachedVeils += 1;
    _syncPulse();
  }

  void _detach() {
    _attachedVeils -= 1;
    _syncPulse();
  }

  /// 紙上的骨架只在畫在畫面上時用呼吸：載入失敗改顯示錯誤、或紙已淡出時
  /// 都放掉，不讓一個看不到的動畫持續要求重畫。
  void _syncPulse() => _setUsingBreath(
    _attachedVeils > 0 &&
        !_reduceMotion &&
        !_cover.isDismissed &&
        (_skeleton.value > 0 || _skeleton.isAnimating),
  );

  void _setUsingBreath(bool value) {
    if (_usingBreath == value) return;
    _usingBreath = value;
    if (value) {
      _breath.acquire();
    } else {
      _breath.release();
    }
  }
}

/// [LoadingVeilController] 的畫面：撐滿正文區，紙往上下多畫到正文與頁首
/// 頁尾之間的空隙；不攔觸控（呼叫端決定）。
class LoadingVeil extends StatefulWidget {
  const LoadingVeil({
    super.key,
    required this.controller,
    required this.spec,
    required this.backgroundColor,
    required this.textColor,
    this.lines,
    this.titleLines = const <int>{},
    this.blockLines = const <int>{},
  });

  final LoadingVeilController controller;

  /// 正文目前的版面：骨架長條的高度照它的字級。
  final ReaderV2LayoutSpec spec;
  final Color backgroundColor;
  final Color textColor;

  /// 這一頁每一行字在正文區的位置：上次離開時記下的
  /// （[ReaderSkeletonPage.lines]），或這次排好的第一頁。還沒有時紙上只有
  /// 底色。
  final List<Rect>? lines;

  /// [lines] 裡章名那幾行的索引：長條照章名與正文的字級比放大。
  final Set<int> titleLines;

  /// [lines] 裡插圖方塊的索引：照整個範圍畫成方塊（ADR 0050）。
  final Set<int> blockLines;

  @override
  State<LoadingVeil> createState() => _LoadingVeilState();
}

class _LoadingVeilState extends State<LoadingVeil> {
  @override
  void initState() {
    super.initState();
    widget.controller._attach();
  }

  @override
  void didUpdateWidget(covariant LoadingVeil oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller._detach();
      widget.controller._attach();
    }
  }

  @override
  void dispose() {
    widget.controller._detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final viewWidth = MediaQuery.maybeSizeOf(context)?.width ?? 0;
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: _LoadingVeilPainter(
          cover: controller._cover,
          skeleton: controller._skeleton,
          pulse: controller._breath.listenable,
          depthAt: controller._breath.depthAt,
          breathing: () =>
              controller._usingBreath && controller._breath.isBreathing,
          look: SkeletonLook.of(context),
          breathSpan: () {
            final box = context.findRenderObject();
            if (box is! RenderBox || !box.hasSize || viewWidth <= 0) {
              return (0, 1);
            }
            return Skeleton.screenSpan(box, viewWidth);
          },
          sweep: () => controller._sweep,
          skeletonSweep: () => controller._skeletonSweep,
          spec: widget.spec,
          lines: widget.lines,
          titleLines: widget.titleLines,
          blockLines: widget.blockLines,
          backgroundColor: widget.backgroundColor,
          textColor: widget.textColor,
        ),
      ),
    );
  }
}

class _LoadingVeilPainter extends CustomPainter {
  _LoadingVeilPainter({
    required this.cover,
    required this.skeleton,
    required this.pulse,
    required this.depthAt,
    required this.breathing,
    required this.look,
    required this.breathSpan,
    required this.sweep,
    required this.skeletonSweep,
    required this.spec,
    required this.lines,
    required this.titleLines,
    required this.blockLines,
    required this.backgroundColor,
    required this.textColor,
  }) : super(repaint: Listenable.merge([cover, skeleton, pulse]));

  /// 紙與骨架出現的進度：經過的時間比例，不套曲線。整頁淡時在這裡套
  /// [AppMotion.fadeCurve]，由左而右時交給 [SkeletonReveal] 每個位置各自套。
  final Animation<double> cover;
  final Animation<double> skeleton;

  /// 呼吸的深淺變了時通知，紙跟著重畫。
  final Listenable pulse;

  /// 橫向位置（螢幕上，0 左緣、1 右緣）現在的呼吸深淺比例。
  final double Function(double u, SkeletonBreath breath) depthAt;

  /// 骨架照 [depthAt] 的深淺畫：呼吸中或收住途中；整片收住了就是最深。
  final bool Function() breathing;
  final SkeletonLook look;

  /// 紙的左右兩緣在螢幕上的位置（[Skeleton.screenSpan]）：呼吸照螢幕位置，
  /// 換頁平移、縮放時和頁首頁尾的骨架接得上；長出與掀紙照紙上的位置。
  final (double, double) Function() breathSpan;

  /// 掀紙是不是由左而右；紙蓋著時不影響畫面。
  final bool Function() sweep;

  /// 骨架出現是不是由左而右；骨架已經完全出現時不影響畫面。
  final bool Function() skeletonSweep;
  final ReaderV2LayoutSpec spec;
  final List<Rect>? lines;
  final Set<int> titleLines;
  final Set<int> blockLines;
  final Color backgroundColor;
  final Color textColor;

  @override
  void paint(Canvas canvas, Size size) {
    final cover = this.cover.value;
    if (cover <= 0) return;
    final coverStrength = AppMotion.fadeCurve.transform(cover);
    // 由左而右掀紙時，紙與骨架在每個橫向位置各自淡出：濃度是 1 減該處
    // 正文的濃度。
    final sweeping = sweep() && cover < 1;
    final stops = sweeping
        ? SkeletonReveal.sweepStops(1 - cover)
        : const <(double, double)>[];
    Paint shade(Color color, double strength) {
      if (!sweeping) {
        return Paint()..color = color.withValues(alpha: color.a * strength);
      }
      return Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(size.width, 0),
          [
            for (final (_, content) in stops)
              color.withValues(alpha: color.a * strength * (1 - content)),
          ],
          [for (final (u, _) in stops) u],
        );
    }

    // 跨在上下緣的那一行畫到正文區外、正文與頁首頁尾之間的空隙裡
    // （HybridScrollView 不裁切，閱讀頁框架裁到空隙為止）；紙也往上下各多
    // 蓋一個正文區高，那半行才跟著紙一起掀開，不會先露出來。
    canvas.drawRect(
      Rect.fromLTRB(0, -size.height, size.width, size.height * 2),
      shade(backgroundColor, sweeping ? 1 : coverStrength),
    );

    final strength =
        AppMotion.fadeCurve.transform(skeleton.value) *
        (sweeping ? 1 : coverStrength);
    if (strength <= 0) return;
    final lines = this.lines;
    if (lines == null) return;
    final style = spec.style;
    final dark =
        ThemeData.estimateBrightnessForColor(backgroundColor) ==
        Brightness.dark;
    final base = Skeleton.tint(textColor, dark: dark, strength: look.strength);
    final breathing = this.breathing();
    // 紙蓋著、骨架由左而右出現時，每個橫向位置照骨架換進來的濃度畫；掀紙
    // 途中照紙的漸層。
    final growing = !sweeping && skeletonSweep() && skeleton.value < 1;
    double layerAt(double u) {
      if (growing) {
        return coverStrength *
            SkeletonReveal.incomingOpacityAt(skeleton.value, u);
      }
      if (sweeping) {
        return strength * (1 - SkeletonReveal.incomingOpacityAt(1 - cover, u));
      }
      return strength;
    }

    final (screenLeft, screenRight) = breathing ? breathSpan() : (0.0, 1.0);
    double alphaAt(double u) =>
        base.a *
        layerAt(u) *
        (breathing
            ? depthAt(screenLeft + (screenRight - screenLeft) * u, look.breath)
            : 1);
    // 沿橫向會變的有：骨架長出來、掀紙與由左而右的呼吸。換場取
    // [SkeletonReveal.sweepStops] 的停點；呼吸每 1/32 個寬度取一點。
    final breathSweeps = breathing && look.breath.lag > 0;
    final points = <double>{0, 1};
    if (growing) {
      points.addAll(SkeletonReveal.sweepStops(skeleton.value).map((s) => s.$1));
    }
    if (sweeping) points.addAll(stops.map((s) => s.$1));
    if (breathSweeps) {
      for (var i = 1; i < 32; i++) {
        points.add(i / 32);
      }
    }
    // 靜止時也用漸層（只有兩端同色）：單色和漸層的顏色進位不同，長完、
    // 收住、掀紙起步這些銜接處換畫法會整片差 1 階（ADR 0022）。靜止時
    // 只畫一次，多一道漸層不花什麼。
    final us = points.toList()..sort();
    final paint = Paint()
      ..shader = ui.Gradient.linear(Offset.zero, Offset(size.width, 0), [
        for (final u in us) base.withValues(alpha: alphaAt(u)),
      ], us);
    final barHeight = style.fontSize * Skeleton.barHeightFactor;
    final titleBarHeight = style.fontSize > 0
        ? barHeight * style.titleFontSize / style.fontSize
        : barHeight;
    final radius = AppRadius.cardXs.topLeft;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (blockLines.contains(i)) {
        canvas.drawRRect(RRect.fromRectAndRadius(line, radius), paint);
        continue;
      }
      final height = titleLines.contains(i) ? titleBarHeight : barHeight;
      final top = line.center.dy - height / 2;
      canvas.drawRRect(
        RRect.fromLTRBR(line.left, top, line.right, top + height, radius),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_LoadingVeilPainter oldDelegate) =>
      oldDelegate.cover != cover ||
      oldDelegate.skeleton != skeleton ||
      oldDelegate.pulse != pulse ||
      oldDelegate.look != look ||
      oldDelegate.spec != spec ||
      !identical(oldDelegate.lines, lines) ||
      !identical(oldDelegate.titleLines, titleLines) ||
      !identical(oldDelegate.blockLines, blockLines) ||
      oldDelegate.backgroundColor != backgroundColor ||
      oldDelegate.textColor != textColor;
}
