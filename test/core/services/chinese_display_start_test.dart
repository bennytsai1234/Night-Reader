import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/core/services/chinese_display.dart';
import 'package:night_reader/core/services/chinese_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 開 App 時的繁簡轉換：第一幀前就照閱讀設定定下模式，字典在背景 isolate
/// 解析；字典好之前要轉換的畫面看 [ChineseDisplay.readyOf] 先等著。
void main() {
  tearDown(() => ChineseDisplay.mode.value = 0);

  testWidgets('the mode is known at once and readiness waits for the '
      'dictionary parsed off the UI isolate', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'flutter.${PreferKey.readerChineseConvert}': 1,
    });
    final prefs = await SharedPreferences.getInstance();
    late bool ready;
    await tester.pumpWidget(
      ChineseDisplayScope(
        child: Builder(
          builder: (context) {
            ready = ChineseDisplay.readyOf(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(ready, isTrue, reason: '不轉換時不必等');

    ChineseDisplay.mode.value = 1;
    await tester.pump();
    expect(ready, isFalse, reason: '要轉換、字典還沒好');
    ChineseDisplay.mode.value = 0;
    await tester.pump();

    // 讀檔與背景 isolate 要真的跑，不能在測試的假時鐘裡等。
    await tester.runAsync(() {
      final start = ChineseDisplay.start(prefs);
      expect(ChineseDisplay.mode.value, 1, reason: '模式在字典載好前就定下來');
      return start;
    });
    await tester.pump();
    expect(ready, isTrue, reason: '字典好了');
    expect(ChineseUtils.s2t('斗罗大陆'), '斗羅大陸');
    expect(ChineseUtils.t2s('斗羅大陸'), '斗罗大陆');
  });
}
