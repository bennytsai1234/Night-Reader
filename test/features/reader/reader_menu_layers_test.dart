import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader/features/menu/reader_menu_palette.dart';
import 'package:night_reader/shared/theme/app_layers.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';

void main() {
  testWidgets('閱讀器面板的卡片照分層：淺色是紙那一階，深色比面板亮一階；分隔線和卡片的差距同 App', (tester) async {
    for (final style in AppStyle.values) {
      for (final brightness in Brightness.values) {
        for (final pureBlack in [true, false]) {
          late ReaderMenuStyle menu;
          late StylePalette palette;
          await tester.pumpWidget(
            MaterialApp(
              theme: buildAppTheme(style, brightness, pureBlack: pureBlack),
              // 換主題不漸變：下一幀就要讀到這一組的配色。
              themeAnimationDuration: Duration.zero,
              home: Builder(
                builder: (context) {
                  menu = ReaderMenuStyle.of(context);
                  palette = StylePalette.of(context);
                  return const SizedBox.shrink();
                },
              ),
            ),
          );
          final reason = '${style.label} ${brightness.name} 純黑 $pureBlack';
          final panel = AppLayers.lightness(palette.readerMenu);
          final card = AppLayers.lightness(menu.backgroundElevated);
          final line = AppLayers.lightness(menu.cardOutline);

          expect(menu.backgroundElevated.a, 1.0, reason: reason);
          if (brightness == Brightness.light) {
            expect(
              card - panel,
              closeTo(AppLayers.cardGapLight, 0.6),
              reason: reason,
            );
          } else {
            expect(
              card - panel,
              closeTo(AppLayers.floatGapDark, 0.6),
              reason: reason,
            );
          }
          final appGap =
              (AppLayers.lightness(palette.border) -
                      AppLayers.lightness(palette.surface))
                  .abs();
          expect((line - card).abs(), closeTo(appGap, 0.6), reason: reason);
        }
      }
    }
  });
}
