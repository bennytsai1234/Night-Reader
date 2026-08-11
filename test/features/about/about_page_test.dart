import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/about/about_page.dart';
import 'package:night_reader/features/about/external_url_launcher.dart';
import 'package:night_reader/shared/theme/app_theme.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: '夜讀',
      packageName: 'com.example.night_reader',
      version: '1.2.3',
      buildNumber: '45',
      buildSignature: '',
      installerStore: null,
    );
  });

  for (final mode in <ThemeMode>[ThemeMode.light, ThemeMode.dark]) {
    testWidgets('About reuses the semantic app icon in $mode', (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: mode,
            home: const AboutPage(),
          ),
        );
        await tester.pumpAndSettle();

        final icon = tester.widget<Image>(
          find.byWidgetPredicate(
            (widget) =>
                widget is Image &&
                widget.image is AssetImage &&
                (widget.image as AssetImage).assetName ==
                    'assets/ui/app_icon.webp',
          ),
        );
        expect(icon.semanticLabel, '夜讀應用程式圖示');
        expect(find.bySemanticsLabel('夜讀應用程式圖示'), findsOneWidget);
        expect(find.text('v1.2.3'), findsOneWidget);
      } finally {
        semantics.dispose();
      }
    });
  }

  testWidgets('external URL failure offers a copy fallback', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder:
              (context) => Scaffold(
                body: FilledButton(
                  onPressed:
                      () => launchExternalUrlWithFeedback(
                        context,
                        'https://example.invalid/night-reader',
                        launcher: (_) async => false,
                      ),
                  child: const Text('開啟連結'),
                ),
              ),
        ),
      ),
    );

    await tester.tap(find.text('開啟連結'));
    await tester.pumpAndSettle();

    expect(find.text('無法開啟連結'), findsOneWidget);
    expect(find.text('複製連結'), findsOneWidget);
  });

  testWidgets('malformed external URL still offers a copy fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder:
              (context) => Scaffold(
                body: FilledButton(
                  onPressed:
                      () =>
                          launchExternalUrlWithFeedback(context, 'http://[::1'),
                  child: const Text('開啟格式錯誤連結'),
                ),
              ),
        ),
      ),
    );

    await tester.tap(find.text('開啟格式錯誤連結'));
    await tester.pumpAndSettle();

    expect(find.text('無法開啟連結'), findsOneWidget);
    expect(find.text('複製連結'), findsOneWidget);
  });
}
