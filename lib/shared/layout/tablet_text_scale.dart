import 'package:flutter/widgets.dart';

/// 平板（畫面短邊至少 [minShortestSide]）上把介面的字整體放大 [factor] 倍，
/// 疊在系統字級上；手機不變。閱讀器正文與頁首頁尾照自己的字號，不跟系統
/// 字級，也就不受影響。2026-11-02 使用者在 1.1、1.15、1.2 的候選圖上選了 1.2。
class TabletTextScale extends StatelessWidget {
  const TabletTextScale({super.key, required this.child});

  /// 視為平板的畫面短邊。
  static const double minShortestSide = 600;

  /// 平板上的放大倍數。
  static const double factor = 1.2;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).shortestSide < minShortestSide) {
      return child;
    }
    final base = MediaQuery.textScalerOf(context);
    return MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: _ScaledTextScaler(base, factor)),
      child: child,
    );
  }
}

/// 系統字級再乘上固定倍數，保留系統的非線性放大。
@immutable
class _ScaledTextScaler extends TextScaler {
  const _ScaledTextScaler(this.base, this.factor);

  final TextScaler base;
  final double factor;

  @override
  double scale(double fontSize) => base.scale(fontSize) * factor;

  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => base.textScaleFactor * factor;

  @override
  bool operator ==(Object other) =>
      other is _ScaledTextScaler &&
      other.base == base &&
      other.factor == factor;

  @override
  int get hashCode => Object.hash(base, factor);
}
