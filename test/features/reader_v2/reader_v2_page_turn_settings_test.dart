import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/constant/prefer_key.dart';

import '../../support/app_harness.dart';
import '../../support/navigation_budget.dart';

// 翻頁的「保留行數」與音量鍵「反向」：照存好的設定打開真的閱讀器，用音量
// 鍵翻頁，量捲了多遠、往哪個方向。
void main() {
  const channel = MethodChannel('night_reader/reader_device');
  TestDefaultBinaryMessenger messenger() =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    messenger().setMockMethodCallHandler(channel, (call) async => null);
  });
  tearDown(() => messenger().setMockMethodCallHandler(channel, null));

  // 預設排版：字號 18、行高 1.4。
  const lineExtent = 18 * 1.4;

  Future<ScrollPosition Function()> open(
    WidgetTester tester,
    Map<String, Object> prefs,
  ) async {
    setUpPhone(tester);
    await tester.runAsync(() async {
      await setUpApp(prefs: {PreferKey.readerVolumeKeyPage: true, ...prefs});
      await seedLibrary();
    });
    await pumpApp(tester);
    await openReader(tester);
    await rest(tester);
    return () =>
        tester.state<ScrollableState>(find.byType(Scrollable).first).position;
  }

  Future<void> pressVolume(WidgetTester tester, {required bool down}) async {
    await messenger().handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(MethodCall('volumeKey', down)),
      (_) {},
    );
    await rest(tester);
  }

  testWidgets('不保留行數時捲過整屏只留 8；反向時音量上翻到下一頁、音量下翻回', (tester) async {
    final position = await open(tester, {
      PreferKey.readerPageTurnOverlap: 0,
      PreferKey.readerVolumeKeyReversed: true,
    });
    final start = position().pixels;

    await pressVolume(tester, down: false);
    expect(
      position().pixels - start,
      closeTo(position().viewportDimension - 8, 0.5),
    );
    await pressVolume(tester, down: true);
    expect(position().pixels, closeTo(start, 0.5));

    await tearDownApp(tester);
  });

  testWidgets('保留 3 行時上一屏最後三行留在畫面上', (tester) async {
    final position = await open(tester, {PreferKey.readerPageTurnOverlap: 3});
    final start = position().pixels;

    await pressVolume(tester, down: true);
    expect(
      position().pixels - start,
      closeTo(position().viewportDimension - 3 * lineExtent - 8, 0.5),
    );

    await tearDownApp(tester);
  });
}
