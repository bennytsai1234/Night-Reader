// 替換規則的匯入預覽：一包 300 條（與對照的 30 條）規則，從點下去到面板
// 滑到位每一幀的成本（ADR 0018）。面板一打開就把每一列建好，這裡量打開
// 那一下主執行緒花多久。用法見 `test/support/frame_budget.dart`；帶
// `frame_budget` 標籤，平常的全套測試跳過。
@Tags(['frame_budget'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/replace_rule.dart';
import 'package:night_reader/features/replace_rule/replace_rule_exchange.dart';
import 'package:night_reader/features/replace_rule/widgets/replace_rule_import_sheet.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';

import '../support/app_harness.dart';
import '../support/navigation_budget.dart';
import '../support/screenshot.dart';

void main() {
  setUpAll(loadScreenshotFonts);

  for (final count in [30, 300]) {
    testWidgets('replace rule import preview with $count rules', (
      tester,
    ) async {
      setUpPhone(tester);
      final preview = ReplaceRuleImportPreview(
        items: [
          for (var i = 0; i < count; i++)
            ReplaceRuleImportItem(
              ReplaceRule(
                id: 1700000000000 + i,
                name: '淨化規則第 $i 條：去掉網站插進正文的廣告字樣',
                group: i.isEven ? '淨化' : null,
                pattern: '廣告$i',
              ),
              i % 3 == 0
                  ? ReplaceRuleImportState.updated
                  : ReplaceRuleImportState.added,
            ),
        ],
        invalidCount: 0,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(AppStyle.paper, Brightness.light),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showReplaceRuleImportSheet(context, preview),
                  child: const Text('打開匯入預覽'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      for (final round in ['第一輪', '第二輪']) {
        await measureNavigation(
          tester,
          '$round 打開 $count 條的匯入預覽',
          action: () => tester.tap(find.text('打開匯入預覽')),
          settled: () => find.text('匯入 $count 個替換規則').evaluate().isNotEmpty,
          note: () => '面板',
        );
        await rest(tester);
        await measureNavigation(
          tester,
          '$round 關掉匯入預覽',
          action: () => goBack(tester),
          settled: () => find.text('匯入 $count 個替換規則').evaluate().isEmpty,
          note: () => '面板',
        );
        await rest(tester);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
