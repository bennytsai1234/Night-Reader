import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'reader_test_support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('西游记 Reader sequential, random jump, scroll, lifecycle journey', (
    tester,
  ) async {
    final previousErrorWidgetBuilder = ErrorWidget.builder;
    final previousFlutterErrorHandler = FlutterError.onError;
    try {
      final harness = ReaderTestHarness(tester);
      await harness.startAndProvision();
      await harness.openBook();

      // The real fixture has a preface at index 0; the first named chapter is
      // index 1. Exercise next/previous boundaries through the visible menu.
      await harness.tapNextChapter();
      await harness.jumpToChapter(0);
      await harness.jumpToChapter(1);
      await harness.jumpToChapter(50);
      await harness.jumpToChapter(3);
      await harness.jumpToChapter(100);
      await harness.jumpToChapter(99);
      await harness.jumpToChapter(0);

      await harness.runScrollMatrix();
      await harness.exerciseLifecycleAndReopen();

      debugPrint(
        'READER_E2E_RESULT status=passed fixture=$readerFixtureHostPath '
        'chapters=${harness.chapters.length}',
      );
    } finally {
      ErrorWidget.builder = previousErrorWidgetBuilder;
      FlutterError.onError = previousFlutterErrorHandler;
    }
  }, timeout: const Timeout(Duration(minutes: 8)));
}
