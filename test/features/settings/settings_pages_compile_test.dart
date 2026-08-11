import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:night_reader/features/about/about_page.dart';
import 'package:night_reader/features/settings/data_privacy_settings_page.dart';
import 'package:night_reader/features/settings/settings_page.dart';
import 'package:night_reader/features/settings/tts_settings_page.dart';
import 'package:night_reader/shared/theme/app_theme.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';

void main() {
  test('Settings pages can be constructed', () {
    expect(() => const AboutPage(), returnsNormally);
    expect(() => const DataPrivacySettingsPage(), returnsNormally);
    expect(() => const SettingsPage(), returnsNormally);
    expect(() => const TtsSettingsPage(), returnsNormally);
  });

  testWidgets('Settings page hides Reading Settings entry', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName == 'assets/ui/app_icon.webp',
      ),
      findsOneWidget,
    );
    expect(find.text('閱讀設定'), findsNothing);
    expect(find.text('朗讀與語音'), findsOneWidget);
  });

  for (final mode in <ThemeMode>[ThemeMode.light, ThemeMode.dark]) {
    testWidgets('Settings panels use clipped Material surfaces in $mode', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: mode,
          home: const SettingsPage(),
        ),
      );

      final panelMaterials = tester
          .widgetList<Material>(find.byType(Material))
          .where((material) {
            final shape = material.shape;
            return material.clipBehavior == Clip.antiAlias &&
                shape is RoundedRectangleBorder &&
                shape.borderRadius == AppRadius.cardLg;
          });
      expect(panelMaterials, hasLength(4));
      expect(find.byType(InkWell), findsWidgets);
    });
  }
}
