import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/settings/reading_settings_page.dart';

import '../../support/app_harness.dart';
import '../../support/navigation_budget.dart';

// 音量鍵由 MainActivity 攔下（見 reader_v2_volume_keys.dart）：測試記下閱讀器
// 告訴原生端「現在攔不攔」，並代替原生端送來攔下的音量鍵。
void main() {
  const channel = MethodChannel('night_reader/reader_device');
  TestDefaultBinaryMessenger messenger() =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final paging = <bool>[];

  setUp(() {
    paging.clear();
    messenger().setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'setVolumeKeyPaging') {
        paging.add(call.arguments as bool);
      }
      return null;
    });
  });
  tearDown(() => messenger().setMockMethodCallHandler(channel, null));

  Future<void> pressVolume(WidgetTester tester, {required bool down}) async {
    await messenger().handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(MethodCall('volumeKey', down)),
      (_) {},
    );
    await rest(tester);
  }

  testWidgets('從閱讀選單的「進階」打開音量鍵翻頁，返回後音量下翻頁、音量上翻回；選單開著時不攔', (tester) async {
    setUpPhone(tester);
    await tester.runAsync(() async {
      await setUpApp();
      await seedLibrary();
    });
    await pumpApp(tester);
    await openReader(tester);
    await rest(tester);
    expect(paging, isNot(contains(true)), reason: '設定關著時音量鍵照常調音量');

    ScrollPosition position() =>
        tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    final start = position().pixels;

    const centre = Offset(196, 420);
    await tester.tapAt(centre);
    await rest(tester);
    await tester.tap(find.text('進階'));
    await rest(tester);
    expect(find.byType(ReadingSettingsPage), findsOneWidget);
    // 閱讀偏好的換頁動畫與骨架換場播完才接受拖曳。
    await rest(tester);
    final toggle = find.text('音量鍵翻頁');
    await tester.scrollUntilVisible(
      toggle,
      300,
      scrollable: find
          .descendant(
            of: find.byType(ReadingSettingsPage),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await rest(tester);
    await tester.tap(toggle);
    await rest(tester);
    expect(paging, isNot(contains(true)), reason: '閱讀偏好蓋著時不攔');
    Navigator.of(tester.element(find.byType(ReadingSettingsPage))).pop();
    await rest(tester);
    expect(paging, isNot(contains(true)), reason: '返回後選單滑回來，還不攔');

    await tester.tapAt(centre);
    await rest(tester);
    expect(paging.last, isTrue, reason: '選單收起後開始攔');

    await pressVolume(tester, down: true);
    expect(position().pixels, greaterThan(start));
    await pressVolume(tester, down: false);
    expect(position().pixels, closeTo(start, 0.5));

    await tester.tapAt(centre);
    await rest(tester);
    expect(paging.last, isFalse, reason: '選單開著時音量鍵照常調音量');
    await tester.tapAt(centre);
    await rest(tester);
    expect(paging.last, isTrue);

    await tearDownApp(tester);
    expect(paging.last, isFalse, reason: '離開閱讀器後不再攔');
  });
}
