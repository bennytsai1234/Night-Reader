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
  /// 中心。[change] 一定會同步執行，不會因為轉場而延後或略過。
  void run({Offset? origin, required VoidCallback change});
}

class _ImmediateThemeReveal implements ThemeReveal {
  const _ImmediateThemeReveal();

  @override
  void run({Offset? origin, required VoidCallback change}) => change();
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

  @override
  void run({Offset? origin, required VoidCallback change}) {
    final boundary = _boundaryKey.currentContext?.findRenderObject();
    if (!mounted ||
        MediaQuery.disableAnimationsOf(context) ||
        boundary is! RenderRepaintBoundary) {
      change();
      return;
    }
    ui.Image? snapshot;
    try {
      // 擷取的是上一幀已經畫好的圖層，就是使用者按下時看到的畫面；蓋圖也在
      // 這個範圍內，連續切換時從目前看到的半途狀態接著暈開。
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
    _snapshot?.dispose();
    setState(() {
      _snapshot = snapshot;
      _origin = Offset(
        local.dx.clamp(0, size.width),
        local.dy.clamp(0, size.height),
      );
    });
    _controller.forward(from: 0);
  }

  void _clear() {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    setState(() => _snapshot = null);
    // 等這一幀不再畫這張圖後再釋放。
    WidgetsBinding.instance.addPostFrameCallback((_) => snapshot.dispose());
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
