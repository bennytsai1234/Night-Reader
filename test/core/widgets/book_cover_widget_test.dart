import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/widgets/book_cover_widget.dart';
import 'package:night_reader/shared/theme/app_theme.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';

void main() {
  for (final mode in <ThemeMode>[ThemeMode.light, ThemeMode.dark]) {
    testWidgets('text cover is localized and semantic in $mode', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: mode,
            home: const Scaffold(
              body: BookCoverWidget(bookName: '夜讀測試書', author: '測試作者'),
            ),
          ),
        );

        expect(find.text('無封面'), findsOneWidget);
        expect(find.text('No Image'), findsNothing);
        expect(find.bySemanticsLabel('《夜讀測試書》封面，作者 測試作者'), findsOneWidget);
        expect(find.bySemanticsLabel('無封面'), findsNothing);

        final fallbackLabel = tester.widget<Text>(find.text('無封面'));
        expect(fallbackLabel.style?.color, AppPalette.ink700);
      } finally {
        semantics.dispose();
      }
    });
  }
}
