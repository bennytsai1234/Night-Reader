import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/widgets/app_dialogs.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:night_reader/shared/widgets/grouped_list_skeleton.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';

/// 書源規則輸入列（Telegram ItemListMultilineInputItem 的紙墨版）：放在
/// [GroupedSection] 內，上方小字標籤與小幫手按鈕，下方等寬字輸入框。
class RuleTextField extends StatelessWidget implements GroupedSkeletonItem {
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

  /// 標籤與輸入框的字樣、小幫手按鈕的大小；骨架照同一份排。
  static final TextStyle _labelStyle = AppTextStyles.uiSm.copyWith(
    fontWeight: FontWeight.w400,
  );
  static final TextStyle _fieldStyle = AppTextStyles.bodySm.copyWith(
    fontFamily: 'monospace',
  );
  static const TextStyle _hintStyle = AppTextStyles.bodySm;
  static const Size _helperSize = Size(AppGrouped.rowMinHeight, 36);
  static const double _helperIconSize = 18;

  /// 上方一列是標籤與小幫手圖示（垂直置中），下面是輸入框的每一行。
  @override
  GroupedItemShape skeletonShape(
    BuildContext context, {
    required double width,
  }) {
    final inner = width - AppGrouped.rowPadding;
    final label = GroupedItemShape.text(
      context,
      this.label,
      style: _labelStyle,
      width: inner - _helperSize.width,
    );
    final labelBlock = AppSpacing.sm + label.height;
    final row = math.max(labelBlock, _helperSize.height);
    final field = groupedTextFieldShape(
      context,
      style: groupedInputStyle(context, _fieldStyle),
      width: inner - AppGrouped.rowPadding,
      text: controller.text,
      hint: hint,
      hintStyle: _hintStyle,
      maxLines: maxLines,
    );
    final iconInset = (_helperSize.width - _helperIconSize) / 2;
    return GroupedItemShape(
      row + field.height + AppSpacing.md,
      marks: [
        ...label.marksAt(Offset(0, (row - labelBlock) / 2 + AppSpacing.sm)),
        SkeletonShape(
          Rect.fromLTWH(
            inner - _helperSize.width + iconInset,
            (row - _helperIconSize) / 2,
            _helperIconSize,
            _helperIconSize,
          ),
          radius: BorderRadius.circular(_helperIconSize / 4),
        ),
        ...field.marksAt(Offset(0, row)),
      ],
    ).padded(const EdgeInsets.only(left: AppGrouped.rowPadding));
  }

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
                    style: _labelStyle.copyWith(color: chrome.sectionText),
                  ),
                ),
              ),
              _buildHelperButton(context),
            ],
          ),
          TextField(
            controller: controller,
            maxLines: maxLines,
            style: _fieldStyle.copyWith(color: scheme.onSurface),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: _hintStyle.copyWith(
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
          child: PressScale(
            onTap: () => _showHelperMenu(context),
            child: SizedBox.fromSize(
              size: _helperSize,
              child: Icon(
                Icons.help_outline_rounded,
                size: _helperIconSize,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showHelperMenu(BuildContext context) async {
    final List<Map<String, String>> helpers = isUrl
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
