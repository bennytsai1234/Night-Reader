// 閱讀選單上方四顆圓鈕長按開各自的完整設定頁，返回後選單回到打開的樣子。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/replace_rule_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/replace_rule.dart';
import 'package:night_reader/features/reader_v2/hybrid/hybrid_reader_screen.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_bottom_menu.dart';
import 'package:night_reader/features/reader_v2/features/replace_rule/reader_v2_replace_rule_page.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_page.dart';
import 'package:night_reader/features/settings/appearance_settings_page.dart';
import 'package:night_reader/features/settings/reading_settings_page.dart';
import 'package:night_reader/features/settings/tts_settings_page.dart';

import '../../support/app_harness.dart';
import '../../support/navigation_budget.dart';

void main() {
  testWidgets('長按圓鈕開那顆鈕的設定頁，返回後選單還開著', (tester) async {
    setUpPhone(tester);
    await tester.runAsync(() async {
      await setUpApp();
      await seedLibrary();
    });
    await pumpApp(tester);
    await openReader(tester);
    await rest(tester);
    await showReaderMenu(tester);

    Finder roundButton(String tooltip) => find.descendant(
      of: find.byType(ReaderV2BottomMenu),
      matching: find.byTooltip(tooltip),
    );
    final dayNight = find.descendant(
      of: find.byType(ReaderV2BottomMenu),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Tooltip &&
            (widget.message == '切換深色模式' || widget.message == '切換淺色模式'),
      ),
    );

    for (final (button, page) in <(Finder, Type)>[
      (roundButton('開始自動翻頁'), ReadingSettingsPage),
      (roundButton('替換規則'), ReaderV2ReplaceRulePage),
      (roundButton('定時朗讀'), TtsSettingsPage),
      (dayNight, AppearanceSettingsPage),
    ]) {
      expect(button, findsOneWidget, reason: '$page 的圓鈕');
      await tester.longPress(button);
      await rest(tester);
      expect(find.byType(page), findsOneWidget, reason: '長按開 $page');
      expect(
        find.byType(ReaderV2Page, skipOffstage: false),
        findsOneWidget,
        reason: '閱讀器留在底下',
      );

      await goBack(tester);
      await rest(tester);
      expect(find.byType(page), findsNothing);
      expect(
        tester
            .widget<ReaderV2BottomMenu>(find.byType(ReaderV2BottomMenu))
            .controlsVisible
            .value,
        isTrue,
        reason: '從 $page 回來，選單滑回打開的樣子',
      );
    }

    await tearDownApp(tester);
  });

  testWidgets('從替換規則鈕長按進去加了規則，回來正文照新規則重排', (tester) async {
    setUpPhone(tester);
    await tester.runAsync(() async {
      await setUpApp();
      await seedLibrary();
    });
    await pumpApp(tester);
    await openReader(tester);
    await rest(tester);
    await showReaderMenu(tester);
    final runtime = tester
        .widget<HybridReaderScreen>(find.byType(HybridReaderScreen))
        .runtime;
    final chapter = runtime.state.visibleLocation.chapterIndex;
    final word = kParagraphs.first.substring(0, 2);

    await tester.longPress(
      find.descendant(
        of: find.byType(ReaderV2BottomMenu),
        matching: find.byTooltip('替換規則'),
      ),
    );
    await rest(tester);
    expect(find.byType(ReaderV2ReplaceRulePage), findsOneWidget);
    await tester.runAsync(
      () => getIt<ReplaceRuleDao>().insert(
        ReplaceRule(
          name: '測試',
          pattern: word,
          replacement: '★★',
          isRegex: false,
        ),
      ),
    );
    await goBack(tester);
    await rest(tester);
    await waitForText(tester);

    final content = (await tester.runAsync(
      () => runtime.loadContentAt(chapter),
    ))!;
    expect(content.displayText, contains('★★'));
    expect(content.displayText, isNot(contains(word)));

    await tearDownApp(tester);
  });
}
