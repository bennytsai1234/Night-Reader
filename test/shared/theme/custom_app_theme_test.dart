import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/shared/navigation/app_page_transition.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';

/// 同一組設定算出的主題要相等：App 根部每次重建都重算一次 `ThemeData`，
/// 不相等時整個 App 讀 `Theme.of` 的元件（含被蓋住的頁面）都跟著重建
/// （ADR 0018）。
void main() {
  ThemeData build({
    AppStyle style = AppStyle.paper,
    Brightness brightness = Brightness.light,
    GlassStrength glassStrength = GlassStrength.frosted,
    AppAccent accent = AppAccent.theme,
    AppPageTransition pageTransition = AppPageTransition.slide,
  }) => buildAppTheme(
    style,
    brightness,
    glassStrength: glassStrength,
    accent: accent,
    pageTransition: pageTransition,
  );

  test('同一組設定連算兩次相等', () {
    for (final style in AppStyle.values) {
      for (final brightness in Brightness.values) {
        for (final accent in AppAccent.values) {
          final a = build(style: style, brightness: brightness, accent: accent);
          final b = build(style: style, brightness: brightness, accent: accent);
          expect(
            a,
            b,
            reason: '${style.name}/${brightness.name}/${accent.name}',
          );
          expect(a.hashCode, b.hashCode);
        }
      }
    }
  });

  test('改一個設定才不相等', () {
    final base = build();
    expect(build(style: AppStyle.values.last), isNot(base));
    expect(build(brightness: Brightness.dark), isNot(base));
    expect(build(glassStrength: GlassStrength.values.last), isNot(base));
    expect(build(accent: AppAccent.values.last), isNot(base));
    expect(build(pageTransition: AppPageTransition.paper), isNot(base));
  });

  test('換頁動畫的 builder 照值比較', () {
    // 不用 const：const 的兩個會是同一個物件，比不出有沒有照值比較。
    final transition = AppPageTransition.slide;
    final a = AppPageTransitionsBuilder(transition);
    final b = AppPageTransitionsBuilder(transition);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(const AppPageTransitionsBuilder(AppPageTransition.zoom)));
  });
}
