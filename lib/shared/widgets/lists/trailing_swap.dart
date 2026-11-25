import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';

/// 列尾的內容互換：兩者交叉淡換，佔的寬度跟著同一段時間與曲線連續變化。
/// 原本 [AnimatedSwitcher] 淡換期間佔兩者中較寬的那個，淡完那一幀才縮成新的
/// 寬度，文字區（例如長網址的「…」）會跳一下。
class TrailingSwap extends StatelessWidget {
  const TrailingSwap({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    // 淡出中的那個比新寬度寬時往左伸出，只在左右方向裁掉，不蓋到文字；
    // 上下照原樣（開關比列尾的空位高也不裁）。
    return ClipRect(
      clipper: const _HorizontalClipper(),
      child: AnimatedSize(
        duration: AppMotion.fade,
        curve: AppMotion.fadeCurve,
        alignment: Alignment.centerRight,
        clipBehavior: Clip.none,
        child: AnimatedSwitcher(
          duration: AppMotion.fade,
          switchInCurve: AppMotion.fadeCurve,
          switchOutCurve: AppMotion.fadeCurve,
          layoutBuilder: _layout,
          child: child,
        ),
      ),
    );
  }

  /// 大小只取新的那個，寬度由外層 [AnimatedSize] 從舊寬度接續；淡出中的
  /// 靠右對齊疊在上面，不撐大版面。
  static Widget _layout(Widget? current, List<Widget> previous) {
    return Stack(
      alignment: Alignment.centerRight,
      clipBehavior: Clip.none,
      children: [
        for (final child in previous) Positioned(right: 0, child: child),
        ?current,
      ],
    );
  }
}

class _HorizontalClipper extends CustomClipper<Rect> {
  const _HorizontalClipper();

  /// 淡出中的那個以新的那個的中線為準上下置中，最高是一列的最小高度
  /// （排序把手），上下各留這麼多就不會被裁到。
  static const double _overhang = AppGrouped.rowMinHeight;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(0, -_overhang, size.width, size.height + _overhang);

  @override
  bool shouldReclip(_HorizontalClipper oldClipper) => false;
}
