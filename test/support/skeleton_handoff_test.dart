import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'skeleton_handoff.dart';

void main() {
  const bar = Rect.fromLTWH(10, 10, 100, 8);

  test('一樣長、同一個位置：對得上', () {
    expect(compareBars([bar], [HandoffMark(bar, '字')]), isEmpty);
  });

  test('一樣長但往下偏了 3：位置不同', () {
    final problems = compareBars(
      [bar],
      [HandoffMark(const Rect.fromLTWH(10, 13, 100, 8), '字')],
    );
    expect(problems.map((p) => p.kind), ['shifted']);
  });

  test('骨架比字短：短了', () {
    final problems = compareBars(
      [bar],
      [HandoffMark(const Rect.fromLTWH(10, 10, 120, 8), '字')],
    );
    expect(problems.map((p) => p.kind), ['short']);
  });
}
