import 'package:flutter/material.dart';
import 'package:reader/shared/theme/app_tokens.dart';
import 'package:reader/shared/theme/app_text_styles.dart';

class RuleTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final int maxLines;
  final bool isUrl;

  const RuleTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint = '',
    this.maxLines = 1,
    this.isUrl = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: AppTextStyles.bodySm.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              _buildHelperButton(context),
            ],
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: controller,
            maxLines: maxLines,
            style: AppTextStyles.bodySm.copyWith(fontFamily: 'monospace'),
            decoration: InputDecoration(
              hintText: hint,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.md,
              ),
              border: OutlineInputBorder(borderRadius: AppRadius.cardSm),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHelperButton(BuildContext context) {
    return IconButton(
      icon: Icon(
        Icons.help_outline,
        size: 20,
        color: Theme.of(context).colorScheme.primary,
      ),
      onPressed: () => _showHelperMenu(context),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
    );
  }

  void _showHelperMenu(BuildContext context) {
    final List<Map<String, String>> helpers =
        isUrl
            ? [
              {'label': '搜尋關鍵字 {{key}}', 'value': '{{key}}'},
              {'label': '分頁佔位符 {{page}}', 'value': '{{page}}'},
              {'label': 'JS 腳本 @js:', 'value': '@js:'},
              {
                'label': 'POST 請求',
                'value':
                    ',{"method": "POST", "body": "key={{key}}&page={{page}}"}',
              },
            ]
            : [
              {'label': 'CSS 選擇器 @css:', 'value': '@css:'},
              {'label': 'XPath 選擇器 //', 'value': '//'},
              {'label': 'JSONPath \$.', 'value': r'$.'},
              {'label': '正規表達式 ##', 'value': '##'},
              {'label': 'JS 腳本 {{js:}}', 'value': '{{js:}}'},
              {'label': '取內容屬性 @text', 'value': '@text'},
              {'label': '取連結屬性 @href', 'value': '@href'},
            ];

    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text(
                  '$label - 規則小幫手',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const Divider(height: 1),
              ...helpers.map(
                (h) => ListTile(
                  title: Text(h['label']!),
                  subtitle: Text(h['value']!),
                  onTap: () {
                    final text = controller.text;
                    final selection = controller.selection;
                    final newText = text.replaceRange(
                      selection.start,
                      selection.end,
                      h['value']!,
                    );
                    controller.text = newText;
                    controller.selection = TextSelection.collapsed(
                      offset: selection.start + h['value']!.length,
                    );
                    Navigator.pop(ctx);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
