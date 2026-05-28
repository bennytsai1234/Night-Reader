import 'package:flutter/material.dart';
import 'package:reader/shared/theme/app_tokens.dart';
import '../widgets/rule_text_field.dart';

class SourceEditContent extends StatelessWidget {
  final Map<String, TextEditingController> controllers;

  const SourceEditContent({super.key, required this.controllers});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        RuleTextField(
          controller: controllers['ruleContentContent']!,
          label: '正文規則',
          hint: '解析章節正文內容',
          maxLines: 5,
        ),
        RuleTextField(
          controller: controllers['ruleContentNextPage']!,
          label: '下一頁規則',
          hint: '分頁正文解析',
        ),
        RuleTextField(
          controller: controllers['ruleContentReplace']!,
          label: '替換規則',
          hint: '##正則##替換內容',
          maxLines: 3,
        ),
      ],
    );
  }
}
