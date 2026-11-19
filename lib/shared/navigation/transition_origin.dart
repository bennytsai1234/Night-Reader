import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 轉場中帶的螢幕圓角（Telegram 的做法）。啟動時向原生端量一次，量不到
/// （舊版 Android、非手機）時為 0，就不加圓角。
abstract final class ScreenCorner {
  static const MethodChannel _channel = MethodChannel(
    'night_reader/system_bars',
  );

  static double radius = 0;

  static Future<void> load() async {
    try {
      radius = await _channel.invokeMethod<double>('screenCornerRadius') ?? 0;
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }
}

/// 「展開」的起點：開啟這頁時按下的那張卡片（[TransitionSource]）或手指
/// 按下的位置，返回時縮回同一處。
///
/// 掛在 App 根部（[TransitionOriginRecorder]）記下最後一次按下的地方，每個
/// 路由第一次建立轉場時取用並記住。沒有按過（例如外部連結開啟）時從畫面
/// 中央展開。
abstract final class TransitionOrigin {
  /// 沒有卡片時，起點的大小：Material 的最小觸控範圍，約等於被點的按鈕。
  static const double _size = kMinInteractiveDimension;

  static TransitionSourceRect? _last;
  static TransitionSourceRect? _pendingSource;
  static final Expando<TransitionSourceRect> _byRoute =
      Expando<TransitionSourceRect>();

  /// 最後一次按下的地方；還沒按過時為 null。
  static TransitionSourceRect? get last => _last;

  static TransitionSourceRect? of(Route<Object?> route) =>
      _byRoute[route] ??= _last;

  /// [point] 周圍一個觸控範圍大小的起點。
  static TransitionSourceRect around(Offset point) => (
    rect: Rect.fromCenter(center: point, width: _size, height: _size),
    radius: _size / 2,
  );
}

/// 起點的範圍與圓角（全域座標）。
typedef TransitionSourceRect = ({Rect rect, double radius});

/// 記下最後一次手指按下的地方，給 [TransitionOrigin] 用；同時量螢幕圓角。
class TransitionOriginRecorder extends StatefulWidget {
  const TransitionOriginRecorder({super.key, required this.child});

  final Widget child;

  @override
  State<TransitionOriginRecorder> createState() =>
      _TransitionOriginRecorderState();
}

class _TransitionOriginRecorderState extends State<TransitionOriginRecorder> {
  @override
  void initState() {
    super.initState();
    unawaited(ScreenCorner.load());
  }

  // 卡片的 Listener 在比較內層，先收到同一次按下並留下自己的範圍。
  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (PointerDownEvent event) {
      TransitionOrigin._last =
          TransitionOrigin._pendingSource ??
          TransitionOrigin.around(event.position);
      TransitionOrigin._pendingSource = null;
    },
    child: widget.child,
  );
}

/// 按下時把自己的範圍交給 [TransitionOrigin]，「展開」從這裡長出來。
/// 包在會開新頁的卡片與列上。
class TransitionSource extends StatelessWidget {
  const TransitionSource({
    super.key,
    this.radius = 0,
    this.area,
    required this.child,
  });

  final double radius;

  /// 從整張卡片的範圍取出要長出來的那一塊（例如書架網格只取封面）；
  /// 沒給時用整張卡片。
  final Rect Function(Rect card)? area;

  final Widget child;

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (_) {
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return;
      final card = box.localToGlobal(Offset.zero) & box.size;
      TransitionOrigin._pendingSource = (
        rect: area?.call(card) ?? card,
        radius: radius,
      );
    },
    child: child,
  );
}
