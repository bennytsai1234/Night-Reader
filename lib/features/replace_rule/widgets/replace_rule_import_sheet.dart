import 'package:flutter/material.dart';
import 'package:night_reader/core/chinese/ui_language.dart';
import 'package:night_reader/core/database/dao/replace_rule_dao.dart';
import 'package:night_reader/core/models/replace_rule.dart';
import 'package:night_reader/features/replace_rule/replace_rule_exchange.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/glass/glass.dart';
import 'package:night_reader/shared/widgets/lists/grouped_list.dart';
import 'package:night_reader/shared/widgets/popups/app_bottom_sheet.dart';
import 'package:night_reader/shared/widgets/text/ui_text.dart';

/// 匯入替換規則都走這一段：解析 [json]、開匯入預覽、匯入勾的、從底部提示
/// 結果（同書源的 `importSourcesWithPreview`）。解析或寫入出錯照樣丟出，由
/// 呼叫的地方提示。
Future<void> importReplaceRulesWithPreview(
  BuildContext context,
  String json, {
  required ReplaceRuleDao dao,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final preview = await previewReplaceRuleImport(json, dao);
  if (!context.mounted) return;
  if (preview.items.isEmpty) {
    messenger.showSnackBar(const SnackBar(content: UiText('未匯入有效替換規則')));
    return;
  }
  final chosen = await showReplaceRuleImportSheet(context, preview);
  if (chosen == null || chosen.isEmpty) return;
  final count = await importReplaceRules(chosen, dao);
  messenger.showSnackBar(SnackBar(content: UiText('成功匯入 $count 個替換規則')));
}

/// 匯入前的底部面板：每一條規則一列，寫名稱（與分組）和它與這台的關係
/// （新增、更新、已有）；新的預設勾，這台已有的預設不勾（同 Legado）。
/// 格式不對、不匯入的數量寫在卡片最後一列。回傳勾選的規則；關掉面板時回傳
/// null。
Future<List<ReplaceRule>?> showReplaceRuleImportSheet(
  BuildContext context,
  ReplaceRuleImportPreview preview,
) {
  final items = preview.items;
  final selected = [for (final item in items) item.selectedByDefault];
  List<ReplaceRule> chosen() => [
    for (var i = 0; i < items.length; i++)
      if (selected[i]) items[i].rule,
  ];
  return AppBottomSheet.showCustom<List<ReplaceRule>>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setState) {
        final count = selected.where((value) => value).length;
        return AppBottomSheet(
          title: '匯入 ${items.length} 個替換規則',
          trailing: GlassTextButton(
            label: count == 0 ? '匯入' : '匯入 $count 個',
            emphasized: true,
            onPressed: count == 0
                ? null
                : () => Navigator.pop(sheetContext, chosen()),
          ),
          children: [
            GroupedSection(
              margin: EdgeInsets.zero,
              topGap: AppSpacing.md,
              children: [
                for (var i = 0; i < items.length; i++)
                  GroupedCheckRow(
                    // 名稱與分組是規則的資料，照原文（ADR 0066）。
                    translate: false,
                    exclusive: false,
                    title: _titleOf(items[i].rule),
                    subtitle: sheetContext.ui(items[i].state.label),
                    selected: selected[i],
                    onTap: () => setState(() => selected[i] = !selected[i]),
                  ),
                if (preview.invalidCount > 0)
                  GroupedRow(
                    title: '格式不對的 ${preview.invalidCount} 個，不匯入',
                    showChevron: false,
                    maxTitleLines: 2,
                  ),
              ],
            ),
          ],
        );
      },
    ),
  );
}

/// 名稱（沒有名稱時寫規則內容），有分組時接在後面（同 Legado）。
String _titleOf(ReplaceRule rule) {
  final name = rule.name.isEmpty ? rule.pattern : rule.name;
  final group = rule.group;
  return group == null || group.isEmpty ? name : '$name ($group)';
}
