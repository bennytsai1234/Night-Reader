import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_window_settings.dart';

void main() {
  const channel = MethodChannel('night_reader/reader_device');
  late List<String> calls;

  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add('${call.method}(${call.arguments})');
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('a full page on top restores the system; coming back reapplies', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const ReaderV2WindowSettings(
          backlight: 0.3,
          child: Scaffold(body: Text('reader')),
        ),
      ),
    );
    expect(calls, ['setKeepScreenOn(true)', 'setWindowBrightness(0.3)']);

    calls.clear();
    showModalBottomSheet<void>(
      context: navigator.currentContext!,
      builder: (_) => const SizedBox(height: 200),
    );
    await tester.pumpAndSettle();
    expect(calls, isEmpty, reason: 'a sheet over the reader is still reading');
    navigator.currentState!.pop();
    await tester.pumpAndSettle();

    navigator.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const Scaffold()),
    );
    await tester.pumpAndSettle();
    expect(calls, ['setKeepScreenOn(false)', 'setWindowBrightness(null)']);

    calls.clear();
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(calls, ['setKeepScreenOn(true)', 'setWindowBrightness(0.3)']);

    calls.clear();
    await tester.pumpWidget(const SizedBox());
    expect(calls, ['setKeepScreenOn(false)', 'setWindowBrightness(null)']);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('following the system never sends a brightness', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ReaderV2WindowSettings(backlight: null, child: SizedBox()),
      ),
    );
    await tester.pumpWidget(const SizedBox());
    expect(calls, ['setKeepScreenOn(true)', 'setKeepScreenOn(false)']);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
