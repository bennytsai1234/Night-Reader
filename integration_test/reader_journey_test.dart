import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'reader_test_support.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('TXT import, directory jump, scroll, background and reopen', (
    tester,
  ) async {
    final errorWidget = ErrorWidget.builder;
    final errorHandler = FlutterError.onError;
    try {
      final reader = ReaderTestHarness(tester);
      await reader.startAndProvision();
      await reader.openBook();
      await reader.jumpFromDirectory(2);
      await reader.jumpFromDirectory(0);
      await reader.jumpFromDirectory(1);
      final location = await reader.scrollAndSave();
      await reader.reopen(location);
      await binding.convertFlutterSurfaceToImage();
      await tester.pump();
      await binding.takeScreenshot('reader-after-reopen');
    } finally {
      ErrorWidget.builder = errorWidget;
      FlutterError.onError = errorHandler;
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
