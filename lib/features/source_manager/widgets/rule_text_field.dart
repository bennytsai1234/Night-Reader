import 'package:flutter/material.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';

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
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
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
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: controller,
            maxLines: maxLines,
            style: AppTextStyles.bodySm.copyWith(fontFamily: 'monospace'),
            decoration: InputDecoration(
              hintText: hint,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.lg,
              ),
              border: const OutlineInputBorder(
                borderRadius: AppRadius.cardMd,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHelperButton(BuildContext context) {
    final semanticsLabel = '開啟$label小幫手';
    return Semantics(
      label: semanticsLabel,
      button: true,
      onTap: () => _showHelperMenu(context),
      child: ExcludeSemantics(
        child: IconButton(
          constraints: const BoxConstraints.tightFor(width: 48, height: 48),
          tooltip: semanticsLabel,
          icon: Icon(
            Icons.help_outline,
            size: 20,
            color: Theme.of(context).colorScheme.primary,
          ),
          onPressed: () => _showHelperMenu(context),
        ),
      ),
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
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Text(
                    '$label - 規則小幫手',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const Divider(height: 1),
                ...helpers.map(
                  (h) => ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xl,
                    ),
                    title: Text(h['label']!),
                    subtitle: Text(h['value']!),
                    onTap: () {
                      final text = controller.text;
                      final selection = controller.selection;
                      final hasValidSelection =
                          selection.isValid &&
                          selection.start >= 0 &&
                          selection.end <= text.length;
                      final start =
                          hasValidSelection ? selection.start : text.length;
                      final end =
                          hasValidSelection ? selection.end : text.length;
                      final value = h['value']!;
                      final newText = text.replaceRange(start, end, value);
                      controller.value = TextEditingValue(
                        text: newText,
                        selection: TextSelection.collapsed(
                          offset: start + value.length,
                        ),
                      );
                      Navigator.pop(ctx);
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
