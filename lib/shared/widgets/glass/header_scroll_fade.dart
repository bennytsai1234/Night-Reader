import 'package:flutter/widgets.dart';

import '../../theme/app_tokens.dart';

/// 捲動清單裡、和玻璃頁首標題重複的字（例如書籍詳情與有聲書播放器清單裡的
/// 書名）：捲到頁首下緣的漸隱帶時跟著捲動淡掉，上緣離工具列下緣還有
/// [distance] 時完全透明。頁首遮罩下緣那一段是淡出（ADR 0075），不淡掉的話
/// 書名會從淡出裡透出來，和頁首標題疊在一起。
///
/// 位置照它在捲動視窗裡的位置算，視窗頂端要是螢幕頂端（頁首蓋在內容上，
/// `extendBodyBehindAppBar`）；頁首沒有工具列下方的附加列。
class HeaderScrollFade extends StatefulWidget {
  const HeaderScrollFade({super.key, required this.child});

  final Widget child;

  /// 從開始淡到完全透明的捲動距離。
  static const double distance = 24;

  @override
  State<HeaderScrollFade> createState() => _HeaderScrollFadeState();
}

class _HeaderScrollFadeState extends State<HeaderScrollFade> {
  final ValueNotifier<double> _opacity = ValueNotifier(1);
  ScrollPosition? _position;

  /// 上緣在整個捲動內容裡的位置（捲到頂時離視窗頂端多遠）。捲動的當下還沒
  /// 重新排版，量畫面位置會是捲動前的；每次排好後量一次，捲動時減掉捲動量。
  double? _contentTop;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (identical(position, _position)) return;
    _position?.removeListener(_update);
    _position = position?..addListener(_update);
  }

  @override
  void dispose() {
    _position?.removeListener(_update);
    _opacity.dispose();
    super.dispose();
  }

  void _measure() {
    if (!mounted) return;
    final position = _position;
    final box = context.findRenderObject() as RenderBox?;
    final viewport = Scrollable.maybeOf(context)?.context.findRenderObject();
    if (position == null ||
        !position.hasPixels ||
        box == null ||
        !box.attached ||
        !box.hasSize ||
        viewport == null) {
      return;
    }
    _contentTop =
        box.localToGlobal(Offset.zero, ancestor: viewport).dy + position.pixels;
    _update();
  }

  void _update() {
    final position = _position;
    final contentTop = _contentTop;
    if (!mounted || position == null || contentTop == null) return;
    // 頁首下緣（工具列下緣再加漸隱帶）：從這裡開始淡。
    final start = AppGlass.headerBottomOf(
      MediaQuery.viewPaddingOf(context).top,
    );
    final top = contentTop - position.pixels;
    _opacity.value =
        ((top - start + HeaderScrollFade.distance) / HeaderScrollFade.distance)
            .clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    return ValueListenableBuilder<double>(
      valueListenable: _opacity,
      builder: (context, opacity, child) =>
          Opacity(opacity: opacity, child: child),
      child: widget.child,
    );
  }
}
