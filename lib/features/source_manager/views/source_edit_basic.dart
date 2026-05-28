import 'package:flutter/material.dart';
import 'package:reader/core/models/book_source.dart';
import 'package:reader/shared/theme/app_tokens.dart';

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
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        _buildField(controllers['name']!, '書源名稱', '例如: 筆趣閣'),
        _buildField(controllers['url']!, '書源網址', '例如: https://example.com'),
        _buildField(controllers['icon']!, '書源圖示', 'URL 或 Base64'),
        _buildField(controllers['group']!, '書源分組', '多個分組用逗號分隔'),
        _buildField(controllers['comment']!, '備註', '自定義備註資訊', maxLines: 3),
        _buildField(
          controllers['header']!,
          '自定義 Header',
          'JSON 格式',
          maxLines: 3,
        ),
      ],
    );
  }

  Widget _buildField(
    TextEditingController controller,
    String label,
    String hint, {
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
