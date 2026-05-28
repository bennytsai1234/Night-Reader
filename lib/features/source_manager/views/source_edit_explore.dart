import 'package:flutter/material.dart';
import 'package:reader/shared/theme/app_tokens.dart';
import '../widgets/rule_text_field.dart';

class SourceEditExplore extends StatelessWidget {
  final Map<String, TextEditingController> controllers;

  const SourceEditExplore({super.key, required this.controllers});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        RuleTextField(
          controller: controllers['exploreUrl']!,
          label: '發現網址',
          hint: '多個用換行或 && 分隔',
          isUrl: true,
          maxLines: 3,
        ),
        RuleTextField(
          controller: controllers['ruleExploreBookList']!,
          label: '列表規則',
          hint: 'JSONPath, XPath 或 CSS',
        ),
        RuleTextField(
          controller: controllers['ruleExploreName']!,
          label: '書名規則',
        ),
        RuleTextField(
          controller: controllers['ruleExploreAuthor']!,
          label: '作者規則',
        ),
        RuleTextField(
          controller: controllers['ruleExploreKind']!,
          label: '分類規則',
        ),
        RuleTextField(
          controller: controllers['ruleExploreWordCount']!,
          label: '字數規則',
        ),
        RuleTextField(
          controller: controllers['ruleExploreLastChapter']!,
          label: '最新章節',
        ),
        RuleTextField(
          controller: controllers['ruleExploreCoverUrl']!,
          label: '封面規則',
        ),
        RuleTextField(
          controller: controllers['ruleExploreBookUrl']!,
          label: '詳情網址規則',
        ),
      ],
    );
  }
}
