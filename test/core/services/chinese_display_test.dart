import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/services/chinese_display.dart';
import 'package:night_reader/core/services/chinese_utils.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 顯示時繁簡轉換的契約：閱讀設定一變，已顯示的書籍資訊就跟著重建；
/// 轉換只作用在顯示，原字串不變。
void main() {
  setUpAll(() {
    ChineseUtils.initializeFromDictionaryData([
      for (final path in ChineseUtils.dictionaryAssetPaths)
        File(path).readAsStringSync(),
    ]);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    ChineseDisplay.mode.value = 0;
  });

  testWidgets('changing the reader setting re-renders shown book names', (
    tester,
  ) async {
    const rawName = '斗罗大陆';
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => ChineseDisplayScope(child: child!),
        home: Builder(builder: (context) => Text(context.zh(rawName))),
      ),
    );
    expect(find.text(rawName), findsOneWidget);

    final settings = ReaderV2SettingsController()..setChineseConvert(1);
    await tester.pump();
    expect(find.text('斗羅大陸'), findsOneWidget);

    settings.setChineseConvert(0);
    await tester.pump();
    expect(find.text(rawName), findsOneWidget);
    settings.dispose();
  });
}
