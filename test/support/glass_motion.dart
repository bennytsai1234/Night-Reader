// 玻璃動畫的檢查（ADR 0022）。

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// 畫面上每一塊玻璃（[BackdropFilter]）上方都沒有半透明的圖層。
///
/// 透明度不到 1 時，模糊取樣的是那一層自己的空白畫布、不是底下的畫面，
/// 到 1 的那一幀才突然糊上去。只量 [FadeTransition] 的數值看不出這件事，
/// 所以在動畫途中呼叫這個檢查。
void expectNoGlassUnderFade(WidgetTester tester) {
  final filters = find.byType(BackdropFilter).evaluate().toList();
  expect(filters, isNotEmpty, reason: '這一幀沒有玻璃，檢查不到東西');
  for (final element in filters) {
    for (
      RenderObject? node = element.renderObject?.parent;
      node != null;
      node = node.parent
    ) {
      final opacity = switch (node) {
        RenderOpacity(:final opacity) => opacity,
        RenderAnimatedOpacity(:final opacity) => opacity.value,
        _ => 1.0,
      };
      expect(
        opacity <= 0 || opacity >= 1,
        isTrue,
        reason: '玻璃包在透明度 $opacity 的圖層裡：${element.widget}',
      );
    }
  }
}
