import 'package:flutter/material.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/widgets/app_dialogs.dart';

/// 書源規則輸入列（Telegram ItemListMultilineInputItem 的紙墨版）：放在
/// [GroupedSection] 內，上方小字標籤與小幫手按鈕，下方等寬字輸入框。
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
    final chrome = AppChrome.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: AppGrouped.rowPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(
                    label,
                    style: AppTextStyles.uiSm.copyWith(
                      color: chrome.sectionText,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ),
              _buildHelperButton(context),
            ],
          ),
          TextField(
            controller: controller,
            maxLines: maxLines,
            style: AppTextStyles.bodySm.copyWith(
              fontFamily: 'monospace',
              color: scheme.onSurface,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: AppTextStyles.bodySm.copyWith(
                color: chrome.sectionText.withValues(alpha: 0.7),
              ),
              isDense: true,
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.only(
                right: AppGrouped.rowPadding,
                bottom: AppSpacing.md,
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
        child: Tooltip(
          message: semanticsLabel,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _showHelperMenu(context),
            child: SizedBox(
              width: AppGrouped.rowMinHeight,
              height: 36,
              child: Icon(
                Icons.help_outline_rounded,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showHelperMenu(BuildContext context) async {
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

    final value = await showAppActionSheet<String>(
      context: context,
      title: '$label - 規則小幫手',
      actions: [
        for (final h in helpers)
          AppSheetAction(
            label: h['label']!,
            subtitle: h['value'],
            value: h['value']!,
          ),
      ],
    );
    if (value == null) return;
    final text = controller.text;
    final selection = controller.selection;
    final hasValidSelection =
        selection.isValid &&
        selection.start >= 0 &&
        selection.end <= text.length;
    final start = hasValidSelection ? selection.start : text.length;
    final end = hasValidSelection ? selection.end : text.length;
    final newText = text.replaceRange(start, end, value);
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + value.length),
    );
  }
}
