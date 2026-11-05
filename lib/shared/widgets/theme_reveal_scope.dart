import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../theme/app_tokens.dart';

/// 切換深淺或風格時的墨暈轉場：新配色從觸發點像墨水一樣暈開，取代瞬間換色。
///
/// 掛在 App 根部（`MaterialApp.builder`），包住所有路由、對話框與選單。
/// 切換的那一下把目前畫面擷取成一張圖蓋在最上層，套用新主題後，圖上由小到
/// 大挖出一個邊緣柔和的圓，露出底下已經是新配色的畫面；轉場結束就移除並
/// 釋放這張圖。只在切換那一下擷取一次，之後每一幀只重畫這層蓋圖。
///
/// 系統動畫關閉（`MediaQuery.disableAnimations`）或擷取失敗時直接換色。
/// 呼叫端不必擔心目前有沒有掛這個元件：找不到時 [of] 回傳直接換色的版本。
class ThemeRevealScope extends StatefulWidget {
  const ThemeRevealScope({super.key, required this.child});

  final Widget child;

  /// 取得最近的墨暈轉場；不在 [ThemeRevealScope] 之下時回傳直接換色的版本。
  static ThemeReveal of(BuildContext context) {
    return context.findAncestorStateOfType<_ThemeRevealScopeState>() ??
        const _ImmediateThemeReveal();
  }

  @override
  State<ThemeRevealScope> createState() => _ThemeRevealScopeState();
}

/// 以墨暈轉場套用一次外觀變更。
abstract interface class ThemeReveal {
  /// 執行 [change]（例如 `setThemeMode`），新配色從 [origin]（螢幕座標）暈開。
  ///
  /// [origin] 為 null 時用觸發這次切換的那一下點擊位置，沒有點擊時用螢幕
  /// 中心。沒在暈開時 [change] 同步執行；暈開中又切換時不打斷正在暈開的
  /// 圓，只記下最後一次，這段播完才執行並暈開（和分頁列連點一樣）。
  ///
  /// [current] 表示要換成的就是現在的設定：不換，暈開中則取消記下的那一次
  /// （例如換到 B、又點 C、再點回 B，停在 B）。
  void run({
    Offset? origin,
    required VoidCallback change,
    bool current = false,
  });
}

class _ImmediateThemeReveal implements ThemeReveal {
  const _ImmediateThemeReveal();

  @override
  void run({
    Offset? origin,
    required VoidCallback change,
    bool current = false,
  }) {
    if (!current) change();
  }
}

/// 墨暈邊緣由濃轉淡的寬度。太窄就只是一個硬邊的圓；太寬則新舊配色在一大片
/// 範圍內混在一起，看起來像整頁淡入。約半個拇指寬，在手機上看得出暈開。
const double _kFeather = 36;

class _ThemeRevealScopeState extends State<ThemeRevealScope>
    with SingleTickerProviderStateMixin
    implements ThemeReveal {
  final GlobalKey _boundaryKey = GlobalKey();
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: AppMotion.themeReveal)
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed) _clear();
        });
  late final CurvedAnimation _progress = CurvedAnimation(
    parent: _controller,
    curve: AppMotion.themeRevealCurve,
  );

  /// 舊畫面的擷取圖；不為 null 時代表轉場進行中。
  ui.Image? _snapshot;
  Offset _origin = Offset.zero;

  /// 最近一次按下的位置（螢幕座標）；呼叫端沒給圓心時用它。
  Offset? _lastPointerDown;

  @override
  void dispose() {
    _progress.dispose();
    _controller.dispose();
    _snapshot?.dispose();
    super.dispose();
  }

  /// 暈開中又要切換的最後一次，這段播完才執行（[_clear]）。
  ({Offset? origin, VoidCallback change})? _pending;

  @override
  void run({
    Offset? origin,
    required VoidCallback change,
    bool current = false,
  }) {
    if (_snapshot != null) {
      // 重拍一張、整個 App 換色重建、圓從零重來，都會落在正在暈開的這段
      // 裡，畫面停一下再跳。
      _pending = current
          ? null
          : (origin: origin ?? _lastPointerDown, change: change);
      return;
    }
    if (current) return;
    final boundary = _boundaryKey.currentContext?.findRenderObject();
    if (!mounted ||
        MediaQuery.disableAnimationsOf(context) ||
        boundary is! RenderRepaintBoundary) {
      change();
      return;
    }
    ui.Image? snapshot;
    try {
      // 擷取的是上一幀已經畫好的圖層，就是使用者按下時看到的畫面。
      snapshot = boundary.toImageSync(
        pixelRatio: View.of(context).devicePixelRatio,
      );
    } catch (_) {
      // 圖層還沒畫好等情況拿不到圖，就直接換色，不擋使用者。
      snapshot = null;
    }
    try {
      change();
    } catch (_) {
      snapshot?.dispose();
      rethrow;
    }
    if (snapshot == null) return;

    final size = boundary.size;
    final point = origin ?? _lastPointerDown;
    final local = point == null
        ? size.center(Offset.zero)
        : boundary.globalToLocal(point);
    setState(() {
      _snapshot = snapshot;
      _origin = Offset(
        local.dx.clamp(0, size.width),
        local.dy.clamp(0, size.height),
      );
    });
    // 換色會讓整個 App 重建，這一幀可能很久；圓從這一幀畫完才開始計時，
    // 不然一開始就跳一段（ADR 0018）。這一幀蓋圖整張蓋著，看起來沒動。
    _controller.value = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(_snapshot, snapshot)) {
        unawaited(_controller.forward(from: 0));
      }
    });
  }

  void _clear() {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    setState(() => _snapshot = null);
    // 等這一幀不再畫這張圖後再釋放。
    WidgetsBinding.instance.addPostFrameCallback((_) => snapshot.dispose());
    // 暈開中記下的那一次：這段的最後一幀畫完之後才拍下一張、換色，和播完
    // 後再點一下一樣，不擠在最後一幀裡。
    if (_pending == null) return;
    Timer.run(() {
      final pending = _pending;
      _pending = null;
      if (!mounted || pending == null) return;
      run(origin: pending.origin, change: pending.change);
    });
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) => _lastPointerDown = event.position,
      child: RepaintBoundary(
        key: _boundaryKey,
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            widget.child,
            if (snapshot != null)
              Positioned.fill(
                // 轉場中照常操作：點擊穿過蓋圖落在底下的新畫面。
                child: IgnorePointer(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _InkRevealPainter(
                        snapshot: snapshot,
                        origin: _origin,
                        progress: _progress,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 畫舊畫面的擷取圖，並從 [origin] 挖掉一個隨 [progress] 長大、邊緣柔和的圓。
class _InkRevealPainter extends CustomPainter {
  _InkRevealPainter({
    required this.snapshot,
    required this.origin,
    required this.progress,
  }) : super(repaint: progress);

  final ui.Image snapshot;
  final Offset origin;
  final Animation<double> progress;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    // 到最遠的角再加上邊緣寬度，結束時整片蓋圖都已挖空。
    final farthest = [
      bounds.topLeft,
      bounds.topRight,
      bounds.bottomLeft,
      bounds.bottomRight,
    ].map((corner) => (corner - origin).distance).reduce(math.max);
    final radius = (farthest + _kFeather) * progress.value;

    canvas.saveLayer(bounds, Paint());
    canvas.drawImageRect(
      snapshot,
      Rect.fromLTWH(
        0,
        0,
        snapshot.width.toDouble(),
        snapshot.height.toDouble(),
      ),
      bounds,
      Paint()..filterQuality = FilterQuality.low,
    );
    if (radius > 0) {
      final solid = math.max(0.0, radius - _kFeather) / radius;
      canvas.drawCircle(
        origin,
        radius,
        Paint()
          ..blendMode = BlendMode.dstOut
          ..shader = ui.Gradient.radial(
            origin,
            radius,
            const [Color(0xFF000000), Color(0xFF000000), Color(0x00000000)],
            [0, solid, 1],
          ),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_InkRevealPainter oldDelegate) =>
      oldDelegate.snapshot != snapshot ||
      oldDelegate.origin != origin ||
      oldDelegate.progress != progress;
}
