import 'package:flutter/material.dart';
import 'package:reader/shared/theme/app_tokens.dart';
import '../widgets/rule_text_field.dart';

class SourceEditBookInfo extends StatelessWidget {
  final Map<String, TextEditingController> controllers;

  const SourceEditBookInfo({super.key, required this.controllers});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        RuleTextField(
          controller: controllers['ruleBookInfoInit']!,
          label: '預處理規則',
          hint: '載入詳情頁前執行',
        ),
        RuleTextField(
          controller: controllers['ruleBookInfoName']!,
          label: '書名規則',
        ),
        RuleTextField(
          controller: controllers['ruleBookInfoAuthor']!,
          label: '作者規則',
        ),
        RuleTextField(
          controller: controllers['ruleBookInfoIntro']!,
          label: '簡介規則',
          maxLines: 2,
        ),
        RuleTextField(
          controller: controllers['ruleBookInfoKind']!,
          label: '分類規則',
        ),
        RuleTextField(
          controller: controllers['ruleBookInfoLastChapter']!,
          label: '最新章節',
        ),
        RuleTextField(
          controller: controllers['ruleBookInfoUpdateTime']!,
          label: '更新時間',
        ),
        RuleTextField(
          controller: controllers['ruleBookInfoCoverUrl']!,
          label: '封面規則',
        ),
        RuleTextField(
          controller: controllers['ruleBookInfoTocUrl']!,
          label: '目錄網址規則',
        ),
        RuleTextField(
          controller: controllers['ruleBookInfoWordCount']!,
          label: '字數規則',
        ),
      ],
    );
  }
}
