import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/settings/reading_settings_page.dart';

import '../../support/app_harness.dart';
import '../../support/navigation_budget.dart';

void main() {
  testWidgets('從閱讀選單的「進階」打開音量鍵翻頁，返回後音量下翻頁、音量上翻回', (tester) async {
    setUpPhone(tester);
    await tester.runAsync(() async {
      await setUpApp();
      await seedLibrary();
    });
    await pumpApp(tester);
    await openReader(tester);
    await rest(tester);

    ScrollPosition position() =>
        tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    final start = position().pixels;

    await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeDown);
    await rest(tester);
    expect(position().pixels, start, reason: '設定關著時音量鍵照常調音量');

    await tester.tapAt(const Offset(196, 420));
    await rest(tester);
    await tester.tap(find.text('進階'));
    await rest(tester);
    expect(find.byType(ReadingSettingsPage), findsOneWidget);
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
    Navigator.of(tester.element(find.byType(ReadingSettingsPage))).pop();
    await rest(tester);
    // 返回後選單滑回來；收起選單才回到閱讀。
    await tester.tapAt(const Offset(196, 420));
    await rest(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeDown);
    await rest(tester);
    final afterDown = position().pixels;
    expect(afterDown, greaterThan(start));

    await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeUp);
    await rest(tester);
    expect(position().pixels, closeTo(start, 0.5));

    await tearDownApp(tester);
  });
}
