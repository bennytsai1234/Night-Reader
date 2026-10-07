import 'package:flutter/material.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import '../widgets/rule_text_field.dart';

class SourceEditSearch extends StatelessWidget {
  final Map<String, TextEditingController> controllers;

  const SourceEditSearch({super.key, required this.controllers});

  @override
  Widget build(BuildContext context) {
    return GroupedListView(
      children: [
        GroupedSection(
          topGap: AppSpacing.sm,
          children: [
            RuleTextField(
              controller: controllers['searchUrl']!,
              label: '搜尋網址',
              hint: '使用 {{key}} 或 {{page}}',
              isUrl: true,
              maxLines: 2,
            ),
          ],
        ),
        GroupedSection(
          header: '搜尋結果',
          children: [
            RuleTextField(controller: controllers['ruleSearchBookList']!, label: '列表規則', hint: 'JSONPath, XPath 或 CSS'),
            RuleTextField(controller: controllers['ruleSearchName']!, label: '書名規則'),
            RuleTextField(controller: controllers['ruleSearchAuthor']!, label: '作者規則'),
            RuleTextField(controller: controllers['ruleSearchKind']!, label: '分類規則'),
            RuleTextField(controller: controllers['ruleSearchWordCount']!, label: '字數規則'),
            RuleTextField(controller: controllers['ruleSearchLastChapter']!, label: '最新章節'),
            RuleTextField(controller: controllers['ruleSearchCoverUrl']!, label: '封面規則'),
            RuleTextField(controller: controllers['ruleSearchNoteUrl']!, label: '詳情網址規則'),
          ],
        ),
      ],
    );
  }
}
