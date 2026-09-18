import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/main.dart' show buildFlutterErrorWidget;

void main() {
  testWidgets(
    'Flutter build failure renders error UI and releases native splash',
    (tester) async {
      var splashReleased = 0;
      final previousBuilder = ErrorWidget.builder;
      final previousOnError = FlutterError.onError;
      addTearDown(() {
        ErrorWidget.builder = previousBuilder;
        FlutterError.onError = previousOnError;
      });

      ErrorWidget.builder = (details) => buildFlutterErrorWidget(
        details,
        releaseNativeSplash: () => splashReleased += 1,
      );
      FlutterError.onError = (_) {};

      await tester.pumpWidget(
        const MaterialApp(home: _ThrowingStartupWidget()),
      );
      await tester.pump();

      expect(find.text('Detected an Error:'), findsOneWidget);
      expect(find.textContaining('provider build failed'), findsOneWidget);
      expect(splashReleased, 1);
    },
  );
}

class _ThrowingStartupWidget extends StatelessWidget {
  const _ThrowingStartupWidget();

  @override
  Widget build(BuildContext context) {
    throw StateError('provider build failed');
  }
}
