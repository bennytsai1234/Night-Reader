import 'package:flutter/material.dart';

/// 亮度拉進加暗段時疊在整個閱讀畫面（含選單）上的黑色；不攔點擊。文字
/// 閱讀器與漫畫閱讀器共用（`docs/design/reader.md`「亮度條」）。
///
/// [child] 不論疊不疊黑都在同一個位置：拖亮度條跨過加暗段那條線時，底下
/// 的閱讀畫面與正在拖的亮度條不重掛。
class ReaderDimOverlay extends StatelessWidget {
  const ReaderDimOverlay({super.key, required this.dim, required this.child});

  /// 黑色的不透明度（0–1）；0 是不疊。
  final double dim;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      child,
      if (dim > 0)
        IgnorePointer(
          child: ColoredBox(color: Colors.black.withValues(alpha: dim)),
        ),
    ],
  );
}
