import 'package:flutter/material.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import '../widgets/rule_text_field.dart';

class SourceEditToc extends StatelessWidget {
  final Map<String, TextEditingController> controllers;

  const SourceEditToc({super.key, required this.controllers});

  @override
  Widget build(BuildContext context) {
    return GroupedListView(
      children: [
        GroupedSection(
          topGap: AppSpacing.sm,
          children: [
            RuleTextField(controller: controllers['ruleTocChapterList']!, label: '目錄列表規則', hint: '解析出章節列表的容器'),
            RuleTextField(controller: controllers['ruleTocChapterName']!, label: '章節名稱規則'),
            RuleTextField(controller: controllers['ruleTocChapterUrl']!, label: '章節網址規則'),
            RuleTextField(controller: controllers['ruleTocNextPage']!, label: '下一頁規則', hint: '多頁目錄分頁'),
          ],
        ),
      ],
    );
  }
}
