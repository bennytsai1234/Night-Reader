import 'package:flutter/material.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';

class SourceEditBasic extends StatelessWidget {
  final BookSource source;
  final Map<String, TextEditingController> controllers;

  const SourceEditBasic({
    super.key,
    required this.source,
    required this.controllers,
  });

  @override
  Widget build(BuildContext context) {
    return GroupedListView(
      children: [
        GroupedSection(
          topGap: AppSpacing.sm,
          header: '基本資訊',
          children: [
            _field(controllers['name']!, '書源名稱', '例如: 筆趣閣'),
            _field(controllers['url']!, '書源網址', '例如: https://example.com'),
            _field(controllers['group']!, '書源分組', '多個分組用逗號分隔'),
          ],
        ),
        GroupedSection(
          header: '備註',
          children: [
            GroupedTextFieldRow(
              controller: controllers['comment']!,
              hintText: '自定義備註資訊',
              maxLines: 3,
            ),
          ],
        ),
        GroupedSection(
          header: '請求',
          children: [
            _field(controllers['loginUrl']!, '登入網址', 'URL 或 @js: 登入腳本'),
          ],
        ),
        GroupedSection(
          header: '自定義 Header',
          children: [
            GroupedTextFieldRow(
              controller: controllers['header']!,
              hintText: 'JSON 格式',
              maxLines: 3,
            ),
          ],
        ),
      ],
    );
  }

  Widget _field(TextEditingController controller, String label, String hint) {
    return GroupedTextFieldRow(
      label: label,
      controller: controller,
      hintText: hint,
    );
  }
}
