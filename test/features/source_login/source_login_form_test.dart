import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/source/source_login_ui.dart';
import 'package:night_reader/features/source_login/source_login_form.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';

import '../../support/screenshot.dart';

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

  // 照字寬排的按鈕，名稱整個放得下，不被截成「…」。
  testWidgets('an auto button shows its whole name', (tester) async {
    await loadScreenshotFonts();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: Scaffold(
          body: SourceLoginButtons(
            buttons: [
              for (final name in ['切換線路', '登入', 'Get token'])
                _button(-1, grow: 0, name: name),
            ],
            onPressed: (_) {},
          ),
        ),
      ),
    );
    for (final name in ['切換線路', '登入', 'Get token']) {
      final paragraph = tester.renderObject<RenderParagraph>(find.text(name));
      expect(paragraph.didExceedMaxLines, isFalse, reason: name);
    }
  });
}
