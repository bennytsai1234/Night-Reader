import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/glass_menu.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';

/// 畫面上 [text] 實際的顏色：字色的透明度乘上祖先 [Opacity] 的透明度。
Color shownColor(WidgetTester tester, String text) {
  final finder = find.text(text).last;
  final widget = tester.widget<Text>(finder);
  final color =
      widget.style?.color ??
      DefaultTextStyle.of(tester.element(finder)).style.color!;
  var alpha = color.a;
  tester.element(finder).visitAncestorElements((element) {
    if (element.widget case Opacity(:final opacity)) alpha *= opacity;
    return true;
  });
  return color.withValues(alpha: alpha);
}

void main() {
  // DESIGN.md 原則 5「選單只有一種樣子」：不能按的東西不管原本是危險色、
  // 強調色還是一般字色，都和選單裡不能用的項目是同一種中性灰。
  for (final brightness in Brightness.values) {
    testWidgets('disabled actions share the disabled menu item grey '
        '(${brightness.name})', (tester) async {
      final theme = buildAppTheme(
        brightness == Brightness.light ? AppStyle.kraft : AppStyle.plain,
        brightness,
        pureBlack: true,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Builder(
            builder: (context) => Scaffold(
              body: Column(
                children: [
                  const PlainTextAction(
                    label: '結束',
                    onPressed: null,
                    destructive: true,
                  ),
                  const PlainTextAction(
                    label: '放到背景',
                    onPressed: null,
                    emphasized: true,
                  ),
                  const GlassTextButton(
                    label: '刪除',
                    onPressed: null,
                    destructive: true,
                  ),
                  const GroupedRow(
                    title: '清除登入資料',
                    destructive: true,
                    enabled: false,
                  ),
                  const GroupedRow(title: '開始找書', accent: true, enabled: false),
                  TextButton(
                    onPressed: () => showGlassMenu<String>(
                      context: context,
                      anchor: const Rect.fromLTWH(20, 400, 40, 40),
                      entries: const [
                        GlassMenuItem(
                          value: 'top',
                          label: '置頂',
                          enabled: false,
                        ),
                        GlassMenuItem(
                          value: 'delete',
                          label: '刪除書源',
                          destructive: true,
                          enabled: false,
                        ),
                      ],
                    ),
                    child: const Text('開'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('開'));
      await tester.pumpAndSettle();

      final grey = theme.colorScheme.onSurface.withValues(
        alpha: AppDisabled.opacity,
      );
      for (final label in [
        '置頂',
        '刪除書源',
        '結束',
        '放到背景',
        '刪除',
        '清除登入資料',
        '開始找書',
      ]) {
        expect(
          shownColor(tester, label).toARGB32(),
          grey.toARGB32(),
          reason: '「$label」停用時應是中性灰',
        );
      }
    });
  }
}
