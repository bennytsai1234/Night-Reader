import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/replace_rule.dart';
import 'package:night_reader/features/replace_rule/replace_rule_exchange.dart';
import 'package:night_reader/features/replace_rule/widgets/replace_rule_import_sheet.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';

void main() {
  testWidgets('匯入預覽列出每一條，已有的預設不勾，勾了才一起匯入', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final preview = ReplaceRuleImportPreview(
      items: [
        ReplaceRuleImportItem(
          ReplaceRule(id: 5, name: '這台有的', pattern: '甲'),
          ReplaceRuleImportState.updated,
        ),
        ReplaceRuleImportItem(
          ReplaceRule(id: 6, name: '新規則', group: '淨化', pattern: '乙'),
          ReplaceRuleImportState.added,
        ),
        ReplaceRuleImportItem(
          ReplaceRule(id: 7, name: '一樣的', pattern: '丙'),
          ReplaceRuleImportState.unchanged,
        ),
      ],
      invalidCount: 2,
    );
    List<ReplaceRule>? chosen;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  chosen = await showReplaceRuleImportSheet(context, preview),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('匯入 3 個替換規則'), findsOneWidget);
    expect(find.text('這台有的'), findsOneWidget);
    expect(find.text('新規則 (淨化)'), findsOneWidget);
    expect(find.text('更新'), findsOneWidget);
    expect(find.text('新增'), findsOneWidget);
    expect(find.text('已有'), findsOneWidget);
    expect(find.text('格式不對的 2 個，不匯入'), findsOneWidget);
    expect(find.text('匯入 1 個'), findsOneWidget);

    await tester.tap(find.text('這台有的'));
    await tester.pumpAndSettle();
    expect(find.text('匯入 2 個'), findsOneWidget);

    await tester.tap(find.text('匯入 2 個'));
    await tester.pumpAndSettle();
    expect([for (final rule in chosen!) rule.id], [5, 6]);
  });
}
