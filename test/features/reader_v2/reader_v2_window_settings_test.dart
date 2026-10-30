import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_orientation.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_window_settings.dart';

void main() {
  const channel = MethodChannel('night_reader/reader_device');
  late List<String> calls;

  setUp(() {
    calls = [];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add('${call.method}(${call.arguments})');
      return null;
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemChrome.setPreferredOrientations') {
        calls.add('orientations(${call.arguments})');
      }
      return null;
    });
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('a full page on top restores the system; coming back reapplies', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const ReaderV2WindowSettings(
          keepScreenOn: true,
          backlight: 0.3,
          orientation: ReaderV2Orientation.system,
          child: Scaffold(body: Text('reader')),
        ),
      ),
    );
    expect(calls, ['setKeepScreenOn(true)', 'setWindowBrightness(0.3)']);

    calls.clear();
    unawaited(
      showModalBottomSheet<void>(
        context: navigator.currentContext!,
        builder: (_) => const SizedBox(height: 200),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, isEmpty, reason: 'a sheet over the reader is still reading');
    navigator.currentState!.pop();
    await tester.pumpAndSettle();

    unawaited(
      navigator.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => const Scaffold()),
      ),
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
        home: ReaderV2WindowSettings(
          keepScreenOn: true,
          backlight: null,
          orientation: ReaderV2Orientation.system,
          child: SizedBox(),
        ),
      ),
    );
    await tester.pumpWidget(const SizedBox());
    expect(calls, ['setKeepScreenOn(true)', 'setKeepScreenOn(false)']);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('keep-screen-on switched off leaves the screen to the system', (
    tester,
  ) async {
    Widget reader({required bool keepScreenOn}) => MaterialApp(
      home: ReaderV2WindowSettings(
        keepScreenOn: keepScreenOn,
        backlight: null,
        orientation: ReaderV2Orientation.system,
        child: const SizedBox(),
      ),
    );
    await tester.pumpWidget(reader(keepScreenOn: false));
    expect(calls, isEmpty);

    await tester.pumpWidget(reader(keepScreenOn: true));
    await tester.pumpWidget(reader(keepScreenOn: false));
    expect(calls, ['setKeepScreenOn(true)', 'setKeepScreenOn(false)']);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('a reader replacing another keeps its own window settings', (
    tester,
  ) async {
    // 換源、從書籍詳情回來時新的閱讀頁取代舊的；舊頁蓋住、拆掉時不能把
    // 新頁的設定恢復成系統設定。動畫中舊頁也會重建。
    final navigator = GlobalKey<NavigatorState>();
    var oldBacklight = 0.3;
    late StateSetter setOld;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: StatefulBuilder(
          builder: (context, setState) {
            setOld = setState;
            return ReaderV2WindowSettings(
              keepScreenOn: true,
              backlight: oldBacklight,
              orientation: ReaderV2Orientation.landscape,
              child: const Scaffold(body: Text('old')),
            );
          },
        ),
      ),
    );
    calls.clear();

    unawaited(
      navigator.currentState!.pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => const ReaderV2WindowSettings(
            keepScreenOn: true,
            backlight: 0.5,
            orientation: ReaderV2Orientation.landscape,
            child: Scaffold(body: Text('new')),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    setOld(() => oldBacklight = 0.4);
    await tester.pumpAndSettle();

    expect(find.text('old'), findsNothing);
    expect(calls, ['setWindowBrightness(0.5)']);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('a locked orientation holds only while the reader shows', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const ReaderV2WindowSettings(
          keepScreenOn: false,
          backlight: null,
          orientation: ReaderV2Orientation.landscape,
          child: Scaffold(body: Text('reader')),
        ),
      ),
    );
    const landscape =
        'orientations([DeviceOrientation.landscapeLeft, '
        'DeviceOrientation.landscapeRight])';
    expect(calls, [landscape]);

    calls.clear();
    unawaited(
      navigator.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => const Scaffold()),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, ['orientations([])']);

    calls.clear();
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(calls, [landscape]);

    calls.clear();
    await tester.pumpWidget(const SizedBox());
    expect(calls, ['orientations([])']);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
