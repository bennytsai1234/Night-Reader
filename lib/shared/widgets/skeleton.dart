import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../theme/app_tokens.dart';

import 'cover_reveal.dart';
import 'launch_entrance.dart';
import 'painted_when.dart';
import 'skeleton_reveal.dart';
import 'snapshot_sweep.dart';

/// 骨架的深淺：佔位底色是文字色疊上這個透明度。幾組數值是原型上比過的
/// （2026-10-20）；使用者在素色深色的閱讀器上看不到原本的骨架，選了
/// [standard]，App 固定用它（不給選，ADR 0024）。[faintest] 是原本的值。
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
}

/// 骨架怎麼呼吸；App 固定用 [gentleSweep]（不給選，ADR 0024）。每個位置照同一個節奏由深
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
  late final _BreathClock _clock = _BreathClock(this);
  bool _breathing = false;

  /// 開 App 的進場收住呼吸時登記在這裡（[LaunchEntranceMotion.rest]）。
  SkeletonRest? _rest;

  /// 所在的開 App 進場；骨架開始呼吸前不呼吸（[_BreathClock.holdUntil]）。
  LaunchEntranceMotion? _entrance;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _breathing = !MediaQuery.disableAnimationsOf(context);
    _clock
      ..breath = SkeletonLook.of(context).breath
      ..allowed = _breathing
      ..visible = TickerMode.valuesOf(context).enabled;
    final entrance = LaunchEntrance.maybeOf(context);
    final rest = entrance?.rest;
    if (!identical(rest, _rest)) {
      _rest?._clocks.remove(_clock);
      _rest = rest?.._add(_clock);
    }
    if (!identical(entrance, _entrance)) {
      _entrance = entrance;
      if (entrance != null) _clock.holdUntil(entrance);
    }
  }

  @override
  void dispose() {
    _rest?._clocks.remove(_clock);
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _SkeletonScope(phase: _breathing ? _clock : null, child: widget.child);
}

/// 收住一群 [Skeleton] 的呼吸：每個位置把這一口氣呼完、停在最深，整個畫面
/// 靜止下來。開 App 書架換場前用（[LaunchEntranceMotion.reveal]，ADR 0031）：
/// 拍定格畫面的那幾格畫面一定停住，停在呼吸自然停下的地方才看不出來。
class SkeletonRest {
  final Set<_BreathClock> _clocks = {};

  /// 從 [settle] 到 [release] 之間：這段期間才出現的骨架一出現就停在最深，
  /// 不再開始一口新的氣，收住的總時間不會被拉長。
  bool _resting = false;

  void _add(_BreathClock clock) {
    _clocks.add(clock);
    if (_resting) clock.restNow();
  }

  /// 收住登記著的骨架，全部停在最深時完成：每個位置把這一口呼完，還沒
  /// 輪到的位置呼完第一口，最多再一輪半（開 App 進場一輪是
  /// [LaunchEntranceMotion.breathCycle]）。
  Future<void> settle() async {
    _resting = true;
    while (true) {
      final pending = [
        for (final clock in _clocks)
          if (!clock.still) clock.rest(),
      ];
      if (pending.isEmpty) return;
      await Future.wait(pending);
    }
  }

  /// 收住的骨架接著呼吸（換場播完後還留著的骨架）。
  void release() {
    _resting = false;
    for (final clock in _clocks) {
      clock.resume();
    }
  }
}

/// 一個 [Skeleton] 的呼吸：從開始呼吸起經過了幾輪（不折回 0）。收住時
/// （[rest]）每個位置等到下一次最深就停在那裡：呼吸曲線在最深處的變化是
/// 零，停下來接得上，不是動到一半定住。
class _BreathClock extends ChangeNotifier {
  _BreathClock(TickerProvider vsync) {
    _ticker = vsync.createTicker(_tick);
  }

  late final Ticker _ticker;

  /// 這個骨架怎麼呼吸：收住要等多久看它（由左而右時右邊晚）。
  SkeletonBreath breath = SkeletonBreath.gentleSweep;

  /// 計時器經過的輪數；[_base] 是計時器這次啟動前已經過的輪數。
  double _cycles = 0;
  double _base = 0;

  /// 呼吸從第幾輪算起：收住後接著呼吸時（[resume]）從那一刻重新算，
  /// [_restarted] 時還沒輪到的位置先停在最深。
  double _shift = 0;
  bool _restarted = false;

  /// 呼吸了幾輪（[Skeleton.breathAt] 的相位）。
  double get _phase => _cycles - _shift;

  /// 開始收住時的 [_phase]；null 是照常呼吸。
  double? _restFrom;
  Completer<void>? _rested;

  /// 收住後整個骨架都停在最深了（畫面外的位置也是），計時器停著。
  bool get still => _still;
  bool _still = false;

  /// 可以呼吸（沒有要求減少動態）。不行時計時器停著，收住直接算停好。
  bool _allowed = false;
  set allowed(bool value) {
    _allowed = value;
    if (value) {
      _start();
    } else {
      _ticker.stop();
      _cycles = _base = _shift = 0;
      _restarted = false;
      if (_restFrom != null) _settle();
    }
  }

  /// 畫面上看得到（[TickerMode]）。收住途中被藏起來時直接算停好：看不到
  /// 就沒有跳動可言，也不會等一個不會來的下一格；之後再出現時照樣停在
  /// 最深，等 [resume]。
  set visible(bool value) {
    if (!value && _restFrom != null && !_still) _settle();
  }

  void _start() {
    if (!_allowed || _still || _hold != null || _ticker.isActive) return;
    _base = _cycles;
    _ticker.start();
  }

  /// 呼吸一輪多長：開 App 進場中的骨架照進場的節奏
  /// （[LaunchEntranceMotion.breathCycle]），其他照 [Skeleton.breathCycle]。
  Duration _cycle = Skeleton.breathCycle;

  /// 開 App 的骨架還沒開始呼吸（[holdUntil]）：整片停在最深、計時器不走。
  ValueListenable<bool>? _hold;

  /// 開 App 的骨架長出時與長完後停的那一下不呼吸、每個位置停在最深；
  /// [LaunchEntranceMotion.breathing] 才照由左而右的先後開始第一口氣，起法
  /// 和收住後接著呼吸（[resume]）一樣。長出時就在呼吸的話，長出看起來像
  /// 一口比之後快的氣，長完接到真正的呼吸時頓一下（使用者 2026-10-24 在
  /// 三種做法的逐格錄影上選的，ADR 0025）。進場結束後才建的骨架照一般的
  /// 節奏呼吸。
  void holdUntil(LaunchEntranceMotion entrance) {
    _releaseHold();
    if (entrance.isFinished) return;
    _cycle = LaunchEntranceMotion.breathCycle;
    if (entrance.breathing.value) return;
    _hold = entrance.breathing..addListener(_onBreathing);
    _ticker.stop();
  }

  void _onBreathing() {
    if (!_hold!.value) return;
    _releaseHold();
    _shift = _cycles;
    _restarted = true;
    _start();
    notifyListeners();
  }

  void _releaseHold() {
    _hold?.removeListener(_onBreathing);
    _hold = null;
  }

  void _tick(Duration elapsed) {
    _cycles = _base + elapsed.inMicroseconds / _cycle.inMicroseconds;
    final from = _restFrom;
    if (from != null && _phase - from >= _restLength(from)) _settle();
    notifyListeners();
  }

  /// 收住呼吸，每個位置都停在最深時完成。計時器沒在走時（不呼吸、被
  /// 藏起來）直接算停好。
  Future<void> rest() {
    _restFrom ??= _phase;
    if (_still) return Future<void>.value();
    if (!_ticker.isActive || _ticker.muted) {
      _settle();
      return Future<void>.value();
    }
    return (_rested ??= Completer<void>()).future;
  }

  /// 收住途中才出現的骨架：一出現就停在最深。
  void restNow() {
    _restFrom ??= _phase;
    _settle();
  }

  /// 收住後接著呼吸：從整片最深重新開始，每個位置照由左而右的先後輪到
  /// 才開始變淺，和一開始呼吸一樣接得上，不跳回原本的明暗。開 App 的進場
  /// 播完才會接著呼吸，之後照一般的節奏。
  void resume() {
    if (_restFrom == null) return;
    _restFrom = null;
    _finishRest();
    _rested = null;
    _cycle = Skeleton.breathCycle;
    if (!_still) return;
    _still = false;
    _shift = _cycles;
    _restarted = true;
    _start();
    notifyListeners();
  }

  void _settle() {
    _still = true;
    _ticker.stop();
    _finishRest();
  }

  void _finishRest() {
    final rested = _rested;
    if (rested != null && !rested.isCompleted) rested.complete();
  }

  /// 從第 [from] 輪開始收住，位置 u（延遲 [lag]）再過幾輪停在最深：照常
  /// 呼吸的位置在 (lag·u − from) mod 1 輪後最深；從整片最深重新開始
  /// （[_restarted]）、還沒輪到的位置，要等它呼完第一口（lag·u + 1）才停，
  /// 不能把它開始變淺的那一刻當成呼完（收住的計時器比呼吸的第一格早一點
  /// 時，右邊會整段沒呼吸）。
  double _stopAfter(double from, double u, double lag) {
    final start = lag * u;
    if (_restarted && from < start) return start + 1 - from;
    return (start - from) % 1;
  }

  /// 從第 [from] 輪開始收住，到每個位置都停在最深要再過幾輪（[_stopAfter]
  /// 在 u 從 0 到 1 取最晚的）：最多一輪；還有位置沒輪到時最晚的是右緣，
  /// 最多一輪半。
  double _restLength(double from) {
    if (_restarted && from < breath.lag) {
      return _stopAfter(from, 1, breath.lag);
    }
    final first = -from % 1;
    final last = first + breath.lag;
    return last < 1 ? last : 1;
  }

  /// 位置 [u]（0 畫面左緣、1 右緣）現在的深淺比例（[Skeleton.breathAt]）；
  /// 收住後已經呼到最深的位置停在 1，接著呼吸時還沒輪到的位置也是。
  double depthAt(double u, SkeletonBreath breath) {
    if (_hold != null) return 1;
    final phase = _phase;
    final from = _restFrom;
    if (from != null &&
        (_still || phase - from >= _stopAfter(from, u, breath.lag))) {
      return 1;
    }
    if (_restarted && phase < breath.lag * u) return 1;
    return _breathTable.at(phase, u, breath);
  }

  @override
  void dispose() {
    _releaseHold();
    _ticker.dispose();
    _finishRest();
    super.dispose();
  }
}

class _SkeletonScope extends InheritedWidget {
  const _SkeletonScope({required this.phase, required super.child});

  /// 呼吸；null 是不呼吸（減少動態）。
  final _BreathClock? phase;

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
  final _BreathClock? phase;
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

  _BreathClock? _phase;
  set phase(_BreathClock? value) {
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

  /// 每一幀重畫都用同一支畫筆（畫的當下就記下了），不每次新建。
  final Paint _paint = Paint();

  @override
  void paint(PaintingContext context, Offset offset) {
    if (size.isEmpty) return;
    context.canvas.drawRRect(
      _borderRadius.toRRect(offset & size),
      _breathingPaint(
        _paint,
        this,
        offset,
        Offset.zero & size,
        color: _color,
        phase: _phase,
        breath: _breath,
        viewWidth: _viewWidth,
      ),
    );
  }
}

/// 佔位形狀在呼吸這一刻的畫筆：設好 [paint] 後回傳它。[local] 是形狀在
/// [box] 裡的位置，[offset] 是 [box] 這次畫在圖層上的位置。[toScreen] 是
/// [box] 到螢幕的轉換（[_screenTransform]），一次畫好幾個形狀時由呼叫端算
/// 一次傳進來；null 時這裡算。
///
/// 骨架呼吸時每一格每個形狀都要重畫，這裡是骨架本身每一格的成本：到螢幕
/// 的轉換要沿著元件樹一路往上乘，一個形狀只算一次；曲線查表（[_breathTable]）
/// 不在每個停點重解一次（ADR 0029「用時間換流暢」，留空間給底下準備內容）。
/// 每一格也盡量不產生新的物件：開 App 的呼吸與換場加起來約 1.5 秒，呼吸前
/// 清過記憶體（`_collectGarbage`），這段期間產生的東西撐不滿新生區，Dart 就
/// 不會在動畫途中回收。原本每個形狀每一格都新建畫筆、停點清單與一份轉換
/// （沿元件樹記下每一層），新生區約 20 幀就滿，呼吸 0.9 秒裡固定回收 5 次，
/// 落到哪一幀、停多久看運氣（2026-10-28 量到）。
Paint _breathingPaint(
  Paint paint,
  RenderBox box,
  Offset offset,
  Rect local, {
  required Color color,
  required _BreathClock? phase,
  required SkeletonBreath breath,
  required double viewWidth,
  Matrix4? toScreen,
}) {
  paint.shader = null;
  if (phase == null) {
    paint.color = color;
  } else if (breath.lag == 0 || viewWidth <= 0) {
    paint.color = color.withValues(alpha: color.a * phase.depthAt(0, breath));
  } else {
    // 兩端都換成螢幕座標：換頁途中整頁在平移、縮放，同一個螢幕位置的
    // 骨架才會一樣深。
    final transform = toScreen ?? _screenTransform(box);
    final left =
        MatrixUtils.transformPoint(transform, local.topLeft).dx / viewWidth;
    final right =
        MatrixUtils.transformPoint(transform, local.topRight).dx / viewWidth;
    final span = right - left;
    final rect = local.shift(offset);
    // 呼吸沿橫向是平滑的曲線，每 1/32 個畫面寬取一個停點就看不出折角。
    final count = math.max(2, (span.abs() * 32).ceil() + 1);
    // 漸層建好時已經把顏色與停點抄走，清單可以每一格重用。
    final colors = _gradientColors[count] ??= List<Color>.filled(count, color);
    for (var i = 0; i < count; i++) {
      colors[i] = color.withValues(
        alpha: color.a * phase.depthAt(left + span * i / (count - 1), breath),
      );
    }
    paint.shader = ui.Gradient.linear(
      rect.centerLeft,
      rect.centerRight,
      colors,
      _gradientStops[count] ??= List<double>.unmodifiable([
        for (var i = 0; i < count; i++) i / (count - 1),
      ]),
    );
  }
  return paint;
}

/// [_breathingPaint] 每種停點數重用的顏色清單與停點。
final Map<int, List<Color>> _gradientColors = {};
final Map<int, List<double>> _gradientStops = {};

/// [box] 到螢幕（邏輯像素）的轉換，同 `box.getTransformTo(null)`，但不沿路
/// 記下每一層、不新建矩陣：結果放在共用的 [_toScreen]，下一個形狀算的時候
/// 就被蓋掉，拿到就要用掉。呼吸時每個骨架每一格都要算一次（[_breathingPaint]）。
Matrix4 _screenTransform(RenderObject box) {
  final root = box.owner?.rootNode;
  _toScreen.setIdentity();
  var child = box;
  // 從自己往上，每一層的轉換乘在左邊；最上面那一層（整個畫面到裝置像素）
  // 不算，和 getTransformTo(null) 一樣。
  for (var parent = child.parent; parent != null && !identical(parent, root);) {
    _step.setIdentity();
    parent.applyPaintTransform(child, _step);
    _step.multiply(_toScreen);
    _toScreen.setFrom(_step);
    child = parent;
    parent = child.parent;
  }
  return _toScreen;
}

final Matrix4 _toScreen = Matrix4.identity();
final Matrix4 _step = Matrix4.identity();

/// [Skeleton.breathAt] 先算好的一張表：呼吸曲線只看一輪裡的位置，和相位、
/// 橫向位置無關，開 App 時算一次（513 個點），畫骨架時查表內插，和直接算的
/// 差距遠小於 1/255。
final _BreathTable _breathTable = _BreathTable();

class _BreathTable {
  _BreathTable() {
    for (var i = 0; i <= _steps; i++) {
      _values[i] = Skeleton.breathAt(i / _steps, 0, SkeletonBreath.whole);
    }
  }

  static const int _steps = 512;
  final Float64List _values = Float64List(_steps + 1);

  /// 同 [Skeleton.breathAt]。
  double at(double phase, double u, SkeletonBreath breath) {
    final x = (phase - breath.lag * u) % 1 * _steps;
    // 非常接近 1 的位置乘出來可能剛好是 _steps：落在最後一段。
    final i = math.min(x.floor(), _steps - 1);
    final t = x - i;
    return _values[i] + (_values[i + 1] - _values[i]) * t;
  }
}

/// [SkeletonShapes] 畫的一個形狀：[fill] 為 null 時是跟著呼吸的佔位色，
/// 給了就是不呼吸的實色（例如卡片底）。
@immutable
class SkeletonShape {
  const SkeletonShape(this.rect, {this.radius = AppRadius.cardXs, this.fill});

  final Rect rect;
  final BorderRadius radius;
  final Color? fill;
}

/// 一次畫好一整塊骨架（一組設定卡片：卡片底、組標題條、每列的文字條與
/// 圖示方塊），整塊只有一個元件。換頁的第一格要建的骨架越少越好，一條條
/// [SkeletonBox] 各是好幾個元件（ADR 0029）。
///
/// 寬度撐滿父層、高度是 [height]；[shapes] 照實際寬度給出各形狀在這塊裡的
/// 位置，照順序畫。
class SkeletonShapes extends LeafRenderObjectWidget {
  const SkeletonShapes({super.key, required this.height, required this.shapes});

  final double height;
  final List<SkeletonShape> Function(Size size) shapes;

  @override
  RenderBox createRenderObject(BuildContext context) => _RenderSkeletonShapes(
    height: height,
    shapes: shapes,
    color: Skeleton.colorOf(context),
    phase: _SkeletonScope.maybeOf(context)?.phase,
    breath: SkeletonLook.of(context).breath,
    viewWidth: MediaQuery.sizeOf(context).width,
  );

  @override
  void updateRenderObject(BuildContext context, RenderBox renderObject) {
    (renderObject as _RenderSkeletonShapes)
      ..height = height
      ..shapes = shapes
      ..color = Skeleton.colorOf(context)
      ..phase = _SkeletonScope.maybeOf(context)?.phase
      ..breath = SkeletonLook.of(context).breath
      ..viewWidth = MediaQuery.sizeOf(context).width;
  }
}

class _RenderSkeletonShapes extends _RenderSkeletonBox {
  _RenderSkeletonShapes({
    required this._height,
    required this._shapes,
    required super.color,
    required super.phase,
    required super.breath,
    required super.viewWidth,
  }) : super(borderRadius: BorderRadius.zero);

  double _height;
  set height(double value) {
    if (_height == value) return;
    _height = value;
    markNeedsLayout();
  }

  List<SkeletonShape> Function(Size size) _shapes;
  set shapes(List<SkeletonShape> Function(Size size) value) {
    if (identical(_shapes, value)) return;
    _shapes = value;
    markNeedsPaint();
  }

  @override
  bool get sizedByParent => false;

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(Size(constraints.maxWidth, _height));

  @override
  void performLayout() {
    size = computeDryLayout(constraints);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (size.isEmpty) return;
    final canvas = context.canvas;
    // 整塊到螢幕的轉換只算一次，每個形狀共用。
    Matrix4? toScreen;
    for (final shape in _shapes(size)) {
      final rrect = shape.radius.toRRect(shape.rect.shift(offset));
      final fill = shape.fill;
      canvas.drawRRect(
        rrect,
        fill != null
            ? (_paint
                ..shader = null
                ..color = fill)
            : _breathingPaint(
                _paint,
                this,
                offset,
                shape.rect,
                color: _color,
                phase: _phase,
                breath: _breath,
                viewWidth: _viewWidth,
                toScreen: _phase == null || _breath.lag == 0
                    ? null
                    : toScreen ??= _screenTransform(this),
              ),
      );
    }
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

/// 骨架與真實內容之間的切換：資料到了以骨架換場（[SkeletonReveal] 的方式
/// 與時長）換成內容；重新載入時骨架也照同樣的方式
/// 與時長長回來。
///
/// 預設兩者都撐滿父層（整頁內容區）；可收縮的面板以 [fit] 保留自然高度。
/// [builder] 只在載入完成後才呼叫。
class SkeletonSwitcher extends StatefulWidget {
  const SkeletonSwitcher({
    super.key,
    required this.loading,
    required this.skeleton,
    required this.builder,
    this.waitForCovers,
    this.entrance,
    this.backdrop,
    this.onRevealed,
    this.fit = StackFit.expand,
  });

  final bool loading;
  final Widget skeleton;
  final WidgetBuilder builder;

  /// 骨架換成內容、換場播完的那一刻（內容已經照常排好）。
  final VoidCallback? onRevealed;

  /// 頁面撐滿內容區；依內容收縮的面板沿用自然高度。
  final StackFit fit;

  /// 骨架與內容後面的實色（通常是頁面底色）。給了的話換場只遮骨架一層：
  /// 骨架墊著這個顏色蓋在照常畫出的內容上，由左而右退開；內容不再套動畫
  /// 遮罩、不另開離屏圖層，換場的每一格少合成一張整區大的圖層（ADR 0029）。
  /// 換到一半時是骨架覆蓋著淡出，比兩層交叉淡換的骨架稍微明顯一點。
  /// 後面不是單一實色（例如半透明、漸層或圖片）時留 null，兩層各自淡入淡出。
  final Color? backdrop;

  /// 給了的話，資料到了先在骨架底下建好內容，照這個方式等畫面上的封面
  /// （[CoverReveal]），再連同封面一次換場；不會先出現空白的書卡、封面再
  /// 一張張浮出來。null 時不等。
  final CoverWait? waitForCovers;

  /// 開 App 的進場（書架的骨架，見 [LaunchEntrance]）：骨架照它的進度、以
  /// 骨架換場的方式出現；這段期間資料到了也先不建內容、不換場，播完才接著
  /// 做（ADR 0018）。第一次換成內容時整個主頁面一起照兩張定格畫面換場
  /// （[LaunchEntranceMotion.reveal]，ADR 0031）。null 時骨架一開始就在。
  final LaunchEntranceMotion? entrance;

  @override
  State<SkeletonSwitcher> createState() => _SkeletonSwitcherState();
}

class _SkeletonSwitcherState extends State<SkeletonSwitcher>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    value: widget.loading || _entering ? 0 : 1,
  )..addStatusListener(_onStatus);

  /// 內容出現的進度（經過的時間比例，曲線由 [SkeletonReveal] 套）。
  late final Animation<double> _content = _controller;
  late final Animation<double> _skeleton = ReverseAnimation(_content);

  void _onStatus(AnimationStatus status) {
    setState(() {});
    // 定格換場時內容一下就換好，換場播完才算出現。
    if (status.isCompleted && !widget.loading && _snapshotting == null) {
      widget.onRevealed?.call();
    }
  }

  /// 正在播的定格換場；換場播完或重新載入時清掉。
  SnapshotSweepController? _snapshotting;

  /// 這一次換進來的是哪一層：換成內容，或重新載入時長回骨架。
  SkeletonRevealSide _incoming = SkeletonRevealSide.content;

  /// 這一次換場是不是由左而右。
  bool _sweep = false;

  /// 淡入前等封面的那一輪；等完或重新載入就換掉。
  CoverReveal? _reveal;

  /// 開 App 第一次換場前，資料到了、正在等骨架收住呼吸
  /// （[LaunchEntranceMotion.settleBreath]）；這段期間當作還在載入，內容不建。
  Future<void>? _resting;

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
    if (_controller.isCompleted) widget.entrance?.revealNow();
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
    _resting = null;
    if (widget.loading) {
      // 定格換場還沒播完就要長回骨架：先換回真的畫面，從內容接著長回去。
      // 呼吸前的準備做到一半的話放棄，骨架照常呼吸。
      _snapshotting?.finish();
      _snapshotting = null;
      widget.entrance?.donePreparing();
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
    final wait = widget.waitForCovers;
    final entrance = widget.entrance;
    final launching = entrance != null && !entrance.revealStarted;
    // 開 App 第一次換場前：骨架剛長完、還沒排好呼吸時，等長完那一格畫完
    // 就在底下一次建好內容、等封面、拍好兩張定格畫面（ADR 0035）；來不及
    // 的話等骨架收住呼吸，畫面靜止了才做（ADR 0031）。呼吸的每一格底下都
    // 不做事：拆成一格一小步時，手機稍慢一點，每一步都讓呼吸那一格晚
    // 出來，一路頓頓地走過去。
    if (launching && !entrance.breathSettled && !entrance.preparing) {
      final resting = _resting =
          entrance.requestPreparation() ?? entrance.settleBreath();
      unawaited(
        resting.then((_) {
          if (!mounted || !identical(_resting, resting)) return;
          setState(() => _resting = null);
          if (!widget.loading) _onLoaded();
        }),
      );
      return;
    }
    if (wait != null) {
      final reveal = _reveal = CoverReveal(wait, paced: !launching);
      // 淡回骨架途中又載入完成時，新內容也要從全透明開始等。建畫面途中歸零
      // 會在別人建構時通知聽換場進度的元件；先停住，這一幀畫完再歸零
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
        reveal.settle().whenComplete(() {
          if (mounted && identical(_reveal, reveal)) _revealContent();
        }),
      );
    } else {
      _revealContent();
    }
  }

  void _revealContent() {
    _prepare(SkeletonRevealSide.content);
    // 開 App 的第一次換場由進場整個畫面一起照兩張定格畫面換（ADR 0031）；
    // 之後重新載入照常兩層換場。
    final entrance = widget.entrance;
    if (entrance == null || entrance.revealStarted) {
      _controller.forward();
      return;
    }
    // 拍下骨架畫面後內容一下就換好（這時螢幕上蓋著骨架那張圖），換場由兩張
    // 圖混合播完。
    final snapshot = _snapshotting = entrance.screen;
    bool current() =>
        mounted && identical(_snapshotting, snapshot) && !widget.loading;
    void showContent() {
      if (current()) _controller.value = 1;
    }

    // 呼吸前：先拍好兩張定格畫面、換回骨架，等呼吸收住再接著換場（ADR
    // 0035）。等的這段當作還在載入（[_resting]）：重新載入時拍好的圖放掉
    // （[didUpdateWidget] 的 finish），照呼吸收住後再拍。
    if (entrance.preparing) {
      unawaited(
        entrance
            .capture(
              change: showContent,
              restore: () {
                if (current()) _controller.value = 0;
              },
            )
            .then((_) {
              if (!current()) return;
              final resting = _resting = entrance.settleBreath();
              setState(() {});
              unawaited(
                resting.then((_) {
                  if (!mounted || !identical(_resting, resting)) return;
                  setState(() => _resting = null);
                  if (!widget.loading) _revealContent();
                }),
              );
            }),
      );
      return;
    }
    final played = entrance.reveal(
      change: showContent,
      duration: _controller.duration!,
      sweep: _sweep,
    );
    unawaited(
      played.whenComplete(() {
        if (!mounted || !identical(_snapshotting, snapshot)) return;
        // 骨架層留到換場播完才拿掉（[build]）。
        setState(() => _snapshotting = null);
        if (!widget.loading && _controller.isCompleted) {
          widget.onRevealed?.call();
        }
      }),
    );
  }

  /// 這一次換場照 [SkeletonReveal] 的方式與時長。換場途中反過來時沿用這一輪的方向
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
    // 拍到一半、拍好還沒播或換場中就被拆掉：結束這一輪、放掉圖，骨架照常
    // 呼吸（換場由這個元件接著播，拆掉就沒有人播了）。
    _snapshotting?.finish();
    widget.entrance?.donePreparing();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reveal = _reveal;
    final entrance = _entering ? widget.entrance : null;
    final appearing = entrance?.skeleton;
    final loading = widget.loading || entrance != null || _resting != null;
    // 還沒開始換場：內容建在骨架底下看不到（有墊色時被骨架整個蓋住，沒有
    // 時全透明），例如等封面、開 App 呼吸前就拍好兩張定格畫面時呼吸的那段
    // （ADR 0035）。不畫（手機不必每一格多畫一整頁看不到的書架），也點不到。
    final covered = _controller.isDismissed;
    final hidden = loading || covered || reveal != null && reveal.waiting;
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
              reveal: reveal,
              child: Builder(builder: widget.builder),
            );
    }
    final content = _lastContent;
    final backdrop = widget.backdrop;
    final skeletonLayer = SkeletonRevealLayer(
      key: const ValueKey('skeleton'),
      presence: appearing ?? _skeleton,
      side: SkeletonRevealSide.skeleton,
      incoming: entrance == null ? _incoming : SkeletonRevealSide.skeleton,
      sweep: entrance?.sweep ?? _sweep,
      child: backdrop == null
          ? Skeleton(child: widget.skeleton)
          // 蓋在內容上面時不擋點擊：換場途中已經露出來的書照樣點得到。
          : IgnorePointer(
              child: ColoredBox(
                color: backdrop,
                child: Skeleton(child: widget.skeleton),
              ),
            ),
    );
    // 等封面時內容已經建在骨架底下：有 [backdrop] 時被墊色的骨架整個蓋住，
    // 沒有時是全透明。
    final contentLayer =
        content != null &&
            (!_controller.isDismissed ||
                reveal != null ||
                _snapshotting != null)
        ? SkeletonRevealLayer(
            key: const ValueKey('content'),
            // 有墊色時內容一律照常畫，交叉淡換全由上面的骨架層負責。
            presence: backdrop == null ? _content : kAlwaysCompleteAnimation,
            side: SkeletonRevealSide.content,
            incoming: _incoming,
            sweep: _sweep,
            // 還沒淡入或正在淡出的內容不接點擊、不給讀屏念。
            child: PaintedWhen(
              shown: !covered,
              child: IgnorePointer(
                ignoring: hidden,
                child: ExcludeSemantics(excluding: hidden, child: content),
              ),
            ),
          )
        : null;
    // 開 App 的定格換場播完前骨架層留著（換成內容後全透明、不畫）：呼吸前
    // 拍好兩張圖換回骨架時不必重建整片骨架。
    final showSkeleton = !_controller.isCompleted || _snapshotting != null;
    // 兩層各有 key：另一層進出 Stack 時不會被錯配、重建。有墊色時骨架在
    // 上面蓋住內容；沒有時骨架在下、內容在上，各自淡入淡出。
    return Stack(
      fit: widget.fit,
      children: backdrop == null
          ? [?(showSkeleton ? skeletonLayer : null), ?contentLayer]
          : [?contentLayer, ?(showSkeleton ? skeletonLayer : null)],
    );
  }
}

/// 清單（sliver）版的 [SkeletonSwitcher]：載入中是一段 [skeleton]（一般
/// box）；資料到了先把 [builder] 給的 slivers 在骨架底下排好（全透明，一幀
/// 建一個），全部建好的下一幀才照骨架換場（[SkeletonReveal] 的方式與時長）
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
    presence: _skeleton,
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

class _RenderSliverRevealLayer extends RenderProxySliver {
  _RenderSliverRevealLayer({required this._presence, required this._sweep});

  Animation<double> _presence;
  set presence(Animation<double> value) {
    if (identical(_presence, value)) return;
    if (attached) _presence.removeListener(_onTick);
    _presence = value;
    if (attached) _presence.addListener(_onTick);
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
      SkeletonReveal.incomingOpacityAt(_presence.value, u, sweep: _sweep);
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
    _presence.addListener(_onTick);
    _partial = !_fullyOpaque && !_fullyClear;
  }

  @override
  void detach() {
    _presence.removeListener(_onTick);
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
    final stops = SkeletonReveal.sweepStops(_presence.value);
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
