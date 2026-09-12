import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:night_reader/features/bookshelf/bookshelf_provider.dart';
import 'package:night_reader/features/welcome/main_page.dart';
import 'package:night_reader/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android app boots into the bookshelf', (tester) async {
    final errorWidgetBuilderBeforeApp = ErrorWidget.builder;
    app.main();
    // The integration-test binding owns first-frame scheduling. Release the
    // production splash explicitly so the Android surface is visible while
    // the test pumps the real app tree.
    FlutterNativeSplash.remove();

    try {
      await tester.pump();
      for (var attempt = 0; attempt < 20; attempt += 1) {
        await tester.pump(const Duration(milliseconds: 500));
        if (find.byType(MainPage).evaluate().isNotEmpty) break;
      }

      expect(find.byType(MainPage), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('書架'),
        ),
        findsOneWidget,
      );

      final shelf = Provider.of<BookshelfProvider>(
        tester.element(find.byType(MainPage)),
        listen: false,
      );
      for (var attempt = 0; attempt < 20 && shelf.isLoading; attempt += 1) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(shelf.isLoading, isFalse);
    } finally {
      // The app installs a production ErrorWidget builder in main(). Reset
      // it so flutter_test can restore its own global test state cleanly.
      ErrorWidget.builder = errorWidgetBuilderBeforeApp;
    }
  });
}
