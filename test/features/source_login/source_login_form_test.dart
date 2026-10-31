import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/source/source_login_ui.dart';
import 'package:night_reader/features/source_login/source_login_form.dart';

SourceLoginRow _button(
  double basis, {
  double grow = 1,
  bool wrapBefore = false,
  String name = 'b',
}) => SourceLoginRow(
  name: name,
  type: SourceLoginRowType.button,
  style: SourceLoginRowStyle(
    grow: grow,
    basisPercent: basis,
    wrapBefore: wrapBefore,
  ),
);

List<List<(int, double)>> _layout(List<SourceLoginRow> buttons) => [
  for (final line in layoutSourceLoginButtons(
    buttons,
    300,
    intrinsic: (button) => button.name.length * 10.0,
    gap: 10,
  ))
    [for (final slot in line) (slot.index, slot.width)],
];

void main() {
  // 書源作者照 Legado 的排法設計：0.4 兩顆一列、0.25 因為按鈕間距三顆一列。
  test('lays buttons out like Legado', () {
    expect(_layout([_button(0.4), _button(0.4), _button(0.4)]), [
      [(0, 145.0), (1, 145.0)],
      [(2, 300.0)],
    ]);
    expect(_layout([for (var i = 0; i < 4; i++) _button(0.25)]), [
      [(0, 93.33333333333333), (1, 93.33333333333333), (2, 93.33333333333333)],
      [(3, 300.0)],
    ]);
  });

  test('sizes auto buttons by their text and honours wrapBefore', () {
    expect(
      _layout([
        _button(-1, grow: 0, name: 'abcd'),
        _button(-1, grow: 0, name: 'ab'),
        _button(-1, grow: 0, name: 'x', wrapBefore: true),
      ]),
      [
        [(0, 40.0), (1, 20.0)],
        [(2, 10.0)],
      ],
    );
  });

  test('a button wider than the line is cut to the line', () {
    expect(_layout([_button(1.5, grow: 0)]), [
      [(0, 300.0)],
    ]);
  });
}
