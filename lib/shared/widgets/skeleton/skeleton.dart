/// @docImport 'skeleton_shapes.dart';
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../../theme/app_tokens.dart';

import 'launch_entrance.dart';

export 'skeleton_shapes.dart';
export 'skeleton_switcher.dart';
export 'sliver_skeleton_switcher.dart';

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
  /// 位置算不出來（換頁途中短暫的 NaN、無限大轉換或寬度）時當作整個畫面寬，
  /// 不把 NaN 交給 [breathAt]：NaN 的透明度在換成顏色時就讓整幀繪製失敗
  /// （#203）。
  static (double, double) screenSpan(RenderBox box, double viewWidth) {
    final left = box.localToGlobal(Offset.zero).dx / viewWidth;
    final right = box.localToGlobal(Offset(box.size.width, 0)).dx / viewWidth;
    if (!left.isFinite || !right.isFinite) return (0, 1);
    return (left, right);
  }

  /// 呼吸最淺時保留的深淺比例：再淺就會在紙上消失，看不出形狀。
  static const double _pulseFloor = 0.55;

  /// 呼吸一輪的時長：由深到淺、再由淺到深各一段 [AppMotion.skeletonPulse]。
  static Duration get breathCycle => AppMotion.skeletonPulse * 2;

  /// 所在 [Skeleton] 的呼吸；不在骨架底下、或不呼吸（減少動態）時是 null。
  static SkeletonPhase? phaseOf(BuildContext context) =>
      _SkeletonScope.maybeOf(context)?.phase;

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
    // 先接上共用的呼吸，可以呼吸時才不會先自己計時一幀。
    _clock
      ..follow(SharedSkeletonBreathScope.maybeOf(context))
      ..breath = SkeletonLook.of(context).breath
      ..allowed = _breathing
      ..visible = TickerMode.valuesOf(context).enabled;
    final entrance = LaunchEntrance.maybeOf(context);
    assert(
      entrance == null || SharedSkeletonBreathScope.maybeOf(context) == null,
      '共用的呼吸不和開 App 的進場一起用（見 SharedSkeletonBreathScope）',
    );
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
  Widget build(BuildContext context) => _SkeletonAnchor(
    clock: _clock,
    child: _SkeletonScope(
      phase: _breathing ? _clock : null,
      child: widget.child,
    ),
  );
}

/// [Skeleton] 最外層，登記成呼吸的 [_BreathClock._anchor]；自己不畫東西。
class _SkeletonAnchor extends SingleChildRenderObjectWidget {
  const _SkeletonAnchor({required this.clock, super.child});

  final _BreathClock clock;

  @override
  _RenderSkeletonAnchor createRenderObject(BuildContext context) =>
      _RenderSkeletonAnchor(clock);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSkeletonAnchor renderObject,
  ) {
    renderObject.clock = clock;
  }
}

class _RenderSkeletonAnchor extends RenderProxyBox {
  _RenderSkeletonAnchor(this._clock);

  _BreathClock _clock;
  set clock(_BreathClock value) {
    if (identical(_clock, value)) return;
    if (attached) _release();
    _clock = value;
    if (attached) _clock._anchor = this;
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _clock._anchor = this;
  }

  @override
  void detach() {
    _release();
    super.detach();
  }

  void _release() {
    if (identical(_clock._anchor, this)) _clock._anchor = null;
  }
}

/// 同一個畫面上分開畫的幾塊骨架共用的一口呼吸：閱讀器的紙（自己畫骨架）
/// 與頁首頁尾（[Skeleton]）照同一個相位呼吸，由左而右的明暗才是同一道走
/// 過整個畫面。各自計時的話，誰先出現誰先開始，兩邊的明暗就錯開。
///
/// 和開 App 的骨架一樣（ADR 0025、0035）：一開始整片停在最深，[begin] 才
/// 從最深照由左而右的先後開始呼吸；[settle] 收住，每個位置把這一口呼完、
/// 停在最深。閱讀器的紙長完骨架才開始呼吸，正文排好就收住，在靜止的紙底下
/// 建好正文才掀紙（ADR 0037 策略一、二）。最後一個使用者放掉（[release]）
/// 就回到一開始的樣子。
class SharedSkeletonBreath {
  SharedSkeletonBreath({required TickerProvider vsync})
    : _clock = _BreathClock(vsync).._waiting = true;

  final _BreathClock _clock;

  /// 呼吸的深淺變了（每一幀，或開始、收住、回到最深）時通知。
  Listenable get listenable => _clock;

  /// 照 [depthAt] 畫：有人在用、正在呼吸或收住途中。還沒開始或已經收住
  /// 時整片最深。
  bool get isBreathing => _users > 0 && !_clock._waiting && !_clock.still;

  /// 位置 [u]（0 畫面左緣、1 右緣）現在的深淺比例（[Skeleton.breathAt]）；
  /// 還沒開始、或收住途中已經呼到最深的位置是 1。
  double depthAt(double u, SkeletonBreath breath) => _clock.depthAt(u, breath);

  int _users = 0;

  /// [settle] 或 [begin] 一次就加一，作廢等著收住後再開始的那一次。
  int _requests = 0;

  void acquire() {
    _users += 1;
    _clock.allowed = true;
  }

  void release() {
    _users -= 1;
    // 拆掉後才放掉的（使用它的骨架比它晚拆）：已經沒有要通知的人。
    if (_users == 0 && !_disposed) {
      _requests += 1;
      _clock.reset();
    }
  }

  /// 開始呼吸：還沒開始或已經收住時，從整片最深照由左而右的先後起，接得
  /// 上、不跳。收住途中時等這一口呼完、停在最深再起，不從半途跳回最深。
  /// 已經在呼吸時不做事。
  void begin() {
    final request = ++_requests;
    if (_clock._restFrom != null && !_clock.still) {
      unawaited(
        _clock.rest().then((_) {
          if (request == _requests) _clock.begin();
        }),
      );
      return;
    }
    _clock.begin();
  }

  /// 收住呼吸，每個位置都停在最深時完成：最多再一輪（[Skeleton.breathCycle]），
  /// 從最深剛起步時最多一輪半。還沒開始呼吸時立刻完成。收住後一直停著，
  /// 到 [begin] 或沒人用為止。
  Future<void> settle() {
    _requests += 1;
    return _users == 0 ? Future<void>.value() : _clock.rest();
  }

  bool _disposed = false;

  void dispose() {
    _disposed = true;
    _clock.dispose();
  }
}

/// 讓底下的 [Skeleton] 照 [breath] 呼吸，不自己計時。
///
/// 不和開 App 的進場（[LaunchEntrance]）疊在一起用：進場的停在最深、收住
/// 與接著呼吸都照骨架自己的計時器算，共用的呼吸只有一輪裡的位置，接不上。
class SharedSkeletonBreathScope extends InheritedWidget {
  const SharedSkeletonBreathScope({
    super.key,
    required this.breath,
    required super.child,
  });

  final SharedSkeletonBreath breath;

  static SharedSkeletonBreath? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<SharedSkeletonBreathScope>()
      ?.breath;

  @override
  bool updateShouldNotify(SharedSkeletonBreathScope oldWidget) =>
      !identical(breath, oldWidget.breath);
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

/// 骨架形狀畫的時候讀的呼吸（[Skeleton.phaseOf]）：[SkeletonBox] 這類形狀
/// 聽它重畫，照它的深淺或整片的漸層畫。呼吸怎麼開始、收住、接著呼吸都在
/// [Skeleton] 這一邊，形狀只讀這幾樣。
abstract interface class SkeletonPhase implements Listenable {
  /// 位置 [u]（0 畫面左緣、1 右緣）現在的深淺比例（[Skeleton.breathAt]）。
  double depthAt(double u, SkeletonBreath breath);

  /// 這一刻整個畫面寬的呼吸漸層（螢幕座標）；整片一樣深時是 null，用單色畫。
  ui.Gradient? gradient(Color color, SkeletonBreath breath, double viewWidth);

  /// [box] 到螢幕（邏輯像素）的轉換，同 `box.getTransformTo(null)`。只在
  /// 同一次 paint 裡 [gradient] 不是 null 之後呼叫：骨架最外層到螢幕的那一段
  /// 每一幀算一次，呼吸沒在走時不會作廢。回傳的矩陣是共用的一個，下一個形狀
  /// 算的時候就被蓋掉，拿到就要用掉。
  Matrix4 toScreen(RenderObject box);
}

/// 一個 [Skeleton] 的呼吸：從開始呼吸起經過了幾輪（不折回 0）。收住時
/// （[rest]）每個位置等到下一次最深就停在那裡：呼吸曲線在最深處的變化是
/// 零，停下來接得上，不是動到一半定住。
class _BreathClock extends ChangeNotifier implements SkeletonPhase {
  _BreathClock(TickerProvider vsync) {
    _ticker = vsync.createTicker(_tick);
  }

  /// 這個骨架最外層的 render object（[_SkeletonAnchor]），底下的形狀到螢幕
  /// 的轉換從它接上去（[toScreen]）。換了一個時重算轉換。
  RenderObject? get _anchor => _anchorObject;
  RenderObject? _anchorObject;
  set _anchor(RenderObject? value) {
    _anchorObject = value;
    _anchorStale = true;
  }

  /// [_anchor] 到螢幕的轉換；一幀只沿元件樹往上算一次，底下的形狀只要算到
  /// [_anchor] 為止。
  ///
  /// 用到它的只有由左而右呼吸的時候（[gradient] 不是 null），這時計時器每
  /// 一幀開頭都會走一格（[_tick]，在建畫面與畫圖之前），走一格就作廢；漸層
  /// 的深淺換了（開始呼吸、收住、接著呼吸）也作廢。所以一幀裡第一個要用的
  /// 形狀重算一次，同一幀其他形狀共用。不經過排程直接重畫（測試裡手動 paint）
  /// 時沿用這一幀算好的，那時骨架沒動。
  final Matrix4 _anchorToScreen = Matrix4.identity();
  bool _anchorStale = true;

  /// [_anchor] 這一幀到螢幕的轉換。
  Matrix4 _anchorTransform() {
    if (_anchorStale) {
      _anchorStale = false;
      _walkUp(_anchor!, null, _anchorToScreen);
    }
    return _anchorToScreen;
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
    _syncShared();
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
    if (_visible == value) return;
    _visible = value;
    _syncShared();
    if (value && _shared != null) _onShared();
  }

  bool _visible = true;

  void _start() {
    if (!_allowed ||
        _waiting ||
        _still ||
        _shared != null ||
        _hold != null ||
        _ticker.isActive) {
      return;
    }
    _base = _cycles;
    _ticker.start();
  }

  /// 照這口共用的呼吸走（[SharedSkeletonBreathScope]），自己的計時器不走；
  /// 可以呼吸、畫面上也看得到時登記成它的使用者，它才會呼吸。被藏起來時
  /// 不登記、也不跟著重畫，再出現時接上當下的相位。
  SharedSkeletonBreath? _shared;
  bool _usingShared = false;

  void follow(SharedSkeletonBreath? shared) {
    if (identical(shared, _shared)) return;
    _leaveShared();
    _shared = shared;
    if (shared == null) {
      _start();
      return;
    }
    _ticker.stop();
    shared._clock.addListener(_onShared);
    _syncShared();
    _onShared();
  }

  void _syncShared() {
    final shared = _shared;
    if (shared == null) return;
    final use = _allowed && _visible;
    if (use && !_usingShared) {
      _usingShared = true;
      shared.acquire();
    } else if (!use && _usingShared) {
      _usingShared = false;
      shared.release();
    }
  }

  void _leaveShared() {
    final shared = _shared;
    if (shared == null) return;
    shared._clock.removeListener(_onShared);
    if (_usingShared) {
      _usingShared = false;
      shared.release();
    }
    _shared = null;
  }

  /// 照共用的那口呼吸的狀態畫（含收住與接著呼吸），[depthAt] 與 [gradient]
  /// 算出來和它一樣。
  void _onShared() {
    // 新的一幀：骨架可能換了位置（換頁平移、捲動），同 [_tick]。
    _anchorStale = true;
    final source = _shared!._clock;
    _cycles = source._cycles;
    _shift = source._shift;
    _restFrom = source._restFrom;
    _still = source._still;
    _restarted = source._restarted;
    _waiting = source._waiting;
    if (_visible) notifyListeners();
  }

  /// 呼吸一輪多長：開 App 進場中的骨架照進場的節奏
  /// （[LaunchEntranceMotion.breathCycle]），其他照 [Skeleton.breathCycle]。
  Duration _cycle = Skeleton.breathCycle;

  /// 開 App 的骨架還沒開始呼吸（[holdUntil]）：整片停在最深、計時器不走。
  ValueListenable<bool>? _hold;

  /// 共用的呼吸還沒開始（[SharedSkeletonBreath.begin]）：整片停在最深、
  /// 計時器不走。
  bool _waiting = false;

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
    // 新的一幀：骨架可能換了位置（換頁平移、捲動），時間沒走也一樣。
    _anchorStale = true;
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

  /// 不再呼吸、回到還沒開始的樣子（整片最深、等 [begin]，收住的狀態也
  /// 清掉）：共用的呼吸沒人用時（[SharedSkeletonBreath.release]）。
  void reset() {
    _allowed = false;
    _waiting = true;
    _ticker.stop();
    _cycles = _base = _shift = 0;
    _restarted = false;
    _restFrom = null;
    _still = false;
    _finishRest();
    _rested = null;
    notifyListeners();
  }

  /// 從整片最深開始呼吸，每個位置照由左而右的先後輪到才變淺（同 [resume]）：
  /// 還沒開始（[_waiting]）或已經收住時。
  void begin() {
    if (!_waiting && !_still) return;
    _waiting = false;
    _restFrom = null;
    _finishRest();
    _rested = null;
    _still = false;
    _shift = _cycles;
    _restarted = true;
    _start();
    notifyListeners();
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
  @override
  double depthAt(double u, SkeletonBreath breath) {
    if (_hold != null || _waiting) return 1;
    final phase = _phase;
    final from = _restFrom;
    if (from != null &&
        (_still || phase - from >= _stopAfter(from, u, breath.lag))) {
      return 1;
    }
    if (_restarted && phase < breath.lag * u) return 1;
    return _breathTable.at(phase, u, breath);
  }

  /// 這一刻整個畫面寬的呼吸漸層：螢幕座標從左緣（x = 0）到右緣
  /// （x = [viewWidth]），每 1/32 個畫面寬一個停點，顏色是 [color] 乘上那個
  /// 位置的深淺。同一個骨架每一幀每種顏色只建一道，底下每個形狀共用
  /// （[SkeletonBox] 這類形狀），呼吸每一幀的成本不跟著形狀數變多。整片一樣深時
  /// （還沒開始呼吸、收住了、整片一起呼吸）回傳 null，用單色畫。
  @override
  ui.Gradient? gradient(Color color, SkeletonBreath breath, double viewWidth) {
    // `viewWidth <= 0` 對 NaN 不成立，無限大也一起擋下（#203）。
    if (_hold != null ||
        _waiting ||
        _still ||
        breath.lag == 0 ||
        !viewWidth.isFinite ||
        viewWidth <= 0) {
      return null;
    }
    // 深淺只看這幾個值（[depthAt]）；有一個變了，上一幀的漸層就不能用。
    if (_cachedCycles != _cycles ||
        _cachedShift != _shift ||
        _cachedRestFrom != _restFrom ||
        _cachedRestarted != _restarted ||
        _cachedBreath != breath ||
        _cachedWidth != viewWidth) {
      _gradients.clear();
      _anchorStale = true;
      _cachedCycles = _cycles;
      _cachedShift = _shift;
      _cachedRestFrom = _restFrom;
      _cachedRestarted = _restarted;
      _cachedBreath = breath;
      _cachedWidth = viewWidth;
    }
    return _gradients[color] ??= ui.Gradient.linear(
      Offset.zero,
      Offset(viewWidth, 0),
      [
        for (var i = 0; i < _gradientStops.length; i++)
          color.withValues(alpha: color.a * depthAt(_gradientStops[i], breath)),
      ],
      _gradientStops,
    );
  }

  /// 由左而右呼吸時每個骨架元件每一幀都要算一次（[SkeletonBox] 這類形狀）。
  /// 不沿路記下每一層、不新建矩陣：結果放在共用的 [_toScreen]。只往上算到
  /// 這個骨架的最外層（[_anchor]），再接上那一層這一幀到螢幕的轉換（每個
  /// 骨架一幀算一次）：骨架上面的元件樹（App、頁面、換頁動畫…）比骨架裡面
  /// 深得多，平板書架 69 個形狀每個都從頭算到螢幕時，光這一步每幀約 0.7ms
  /// （2026-11-02 量）。
  @override
  Matrix4 toScreen(RenderObject box) {
    final anchor = _anchor;
    final reached = _walkUp(box, anchor, _toScreen);
    if (anchor != null && identical(reached, anchor)) {
      _step
        ..setFrom(_anchorTransform())
        ..multiply(_toScreen);
      _toScreen.setFrom(_step);
    }
    return _toScreen;
  }

  final Map<Color, ui.Gradient> _gradients = {};
  double? _cachedCycles;
  double? _cachedShift;
  double? _cachedRestFrom;
  bool? _cachedRestarted;
  SkeletonBreath? _cachedBreath;
  double? _cachedWidth;

  @override
  void dispose() {
    _leaveShared();
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

/// [_BreathClock.gradient] 的停點：每 1/32 個畫面寬一個。呼吸沿橫向是平滑的
/// 曲線，這樣分就看不出折角。
final List<double> _gradientStops = List<double>.unmodifiable([
  for (var i = 0; i <= 32; i++) i / 32,
]);

/// 從 [box] 往上，把每一層的轉換乘在左邊，寫進 [into]；走到 [stopAt] 或
/// 最上面那一層（整個畫面到裝置像素，不算，和 getTransformTo(null) 一樣）
/// 為止，回傳停在哪一層。
RenderObject _walkUp(RenderObject box, RenderObject? stopAt, Matrix4 into) {
  final root = box.owner?.rootNode;
  into.setIdentity();
  var child = box;
  for (
    var parent = child.parent;
    parent != null && !identical(parent, root) && !identical(child, stopAt);
  ) {
    _walkStep.setIdentity();
    parent.applyPaintTransform(child, _walkStep);
    _walkStep.multiply(into);
    into.setFrom(_walkStep);
    child = parent;
    parent = child.parent;
  }
  return child;
}

final Matrix4 _toScreen = Matrix4.identity();
final Matrix4 _step = Matrix4.identity();
final Matrix4 _walkStep = Matrix4.identity();

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
