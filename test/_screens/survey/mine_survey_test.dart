// 臨時：全 App 動畫儀表板探索的「我的」區（上半）：「我的」分頁，以及「外觀與主題」
// 的每個選項（風格、強調色、深淺、玻璃效果、換頁動畫）。換頁動畫每一種都選過，
// 再返回、進入一次，讓那一種的換頁看得到。下半在 `mine2_survey_test.dart`。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/shared/widgets/floating_tab_bar.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';

import '../../support/navigation_budget.dart';
import '../../support/screenshot.dart';
import 'survey_support.dart';

const _area = 'mine';

/// 在目前這一頁的清單裡找到 [text]，捲到看得到再點。
Future<void> _tapInList(WidgetTester tester, String text) async {
  final list = find.byType(GroupedListView).last;
  final row = find.descendant(of: list, matching: find.text(text));
  if (row.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      row,
      100,
      scrollable: find
          .descendant(of: list, matching: find.byType(Scrollable))
          .first,
    );
  }
  await tester.ensureVisible(row.first);
  await tester.pump();
  await tester.tap(row.first);
}

/// 點選單或動作表裡的一項。選單浮在最上層，同一個字在下面的列上也可能有，
/// 取最後一個（畫在最上面的那個）。
Future<void> _tapTop(WidgetTester tester, String text) =>
    tester.tap(find.text(text).last);

void main() {
  setUpAll(loadScreenshotFonts);

  testWidgets('survey: mine (appearance)', (tester) async {
    Future<void> tapTab(String label) => tester.tap(
      find.descendant(
        of: find.byType(FloatingTabBar),
        matching: find.text(label),
      ),
    );

    await runSurvey(
      tester,
      steps: () async {
        var i = 0;
        Future<void> step(String label, Future<void> Function() action) {
          i++;
          return surveyStep(
            tester,
            area: _area,
            key: 'mine${i.toString().padLeft(2, '0')}',
            label: label,
            action: action,
            // 點下去後第一格路由還沒蓋出來，不設下限會在 31 格就被當成停了。
            minFrames: 20,
          );
        }

        await step('點分頁：書架→我的', () => tapTab('我的'));
        await step('進入外觀與主題', () => _tapInList(tester, '外觀與主題'));

        // 風格：十種各選一次；最後選回預設的紙墨。
        for (final style in const [
          '竹青',
          '石青',
          '茶褐',
          '素色',
          '胭脂',
          '藕荷',
          '黃卷',
          '琥珀',
          '霜夜',
          '紙墨',
        ]) {
          await step('風格：選$style', () => _tapInList(tester, style));
        }

        // 強調色：十三種各開一次選單、選一次；最後選回跟隨主題。
        for (final accent in const [
          '朱紅',
          '胭脂',
          '琥珀',
          '茶金',
          '黃',
          '竹綠',
          '青綠',
          '天藍',
          '石青',
          '藕荷',
          '灰',
          '墨',
          '跟隨主題',
        ]) {
          await step('強調色：開選單', () => _tapInList(tester, '強調色'));
          await step('強調色：選$accent', () => _tapTop(tester, accent));
        }

        // 深淺：深色、淺色、跟隨系統（最後回到跟隨系統）。
        for (final mode in const ['深色', '淺色', '跟隨系統']) {
          await step('深淺：選$mode', () => _tapInList(tester, mode));
        }

        // 玻璃效果：實色、通透，最後回到霧面。
        for (final strength in const ['實色', '通透', '霧面']) {
          await step('玻璃效果：選$strength', () => _tapInList(tester, strength));
        }

        // 換頁動畫：七種各選一次，返回我的、再進入外觀與主題，讓這一種的換頁看得到。
        for (final transition in const [
          '上浮',
          '平移',
          '滑入',
          '推進',
          '覆蓋',
          '縮放',
          '展開',
        ]) {
          await step('換頁動畫：開選單', () => _tapInList(tester, '換頁動畫'));
          await step('換頁動畫：選$transition', () => _tapTop(tester, transition));
          await step('返回我的（$transition）', () => goBack(tester));
          await step('進入外觀與主題（$transition）', () => _tapInList(tester, '外觀與主題'));
        }
        await step('返回我的', () => goBack(tester));
      },
    );
  });
}
