import 'package:flutter/material.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';

/// 替換規則的基本欄位：名稱、分組、超時，以及正則與替換內容。
class ReplaceEditForm extends StatelessWidget {
  final TextEditingController nameCtrl;
  final TextEditingController groupCtrl;
  final TextEditingController timeoutCtrl;
  final TextEditingController patternCtrl;
  final TextEditingController replacementCtrl;

  /// 分組卡片外距；放在已有左右內距的面板內時傳 [EdgeInsets.zero]。
  final EdgeInsetsGeometry? margin;

  const ReplaceEditForm({
    super.key,
    required this.nameCtrl,
    required this.groupCtrl,
    required this.timeoutCtrl,
    required this.patternCtrl,
    required this.replacementCtrl,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        GroupedSection(
          margin: margin,
          topGap: 0,
          children: [
            ReplaceFormRow(
              controller: nameCtrl,
              label: '規則名稱 *',
              validator: (v) => v!.trim().isEmpty ? '名稱不能為空' : null,
            ),
            ReplaceFormRow(controller: groupCtrl, label: '分組'),
            ReplaceFormRow(
              controller: timeoutCtrl,
              label: '超時 (ms)',
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        GroupedSection(
          margin: margin,
          header: '替換正則內容 *',
          children: [
            ReplaceFormRow(
              controller: patternCtrl,
              maxLines: 3,
              monospace: true,
              validator: (v) => v!.trim().isEmpty ? '正則內容不能為空' : null,
            ),
          ],
        ),
        GroupedSection(
          margin: margin,
          header: '替換為內容',
          children: [
            ReplaceFormRow(
              controller: replacementCtrl,
              maxLines: 3,
              monospace: true,
            ),
          ],
        ),
      ],
    );
  }
}

/// 分組卡片內帶驗證的輸入列；有 [label] 時左側為固定寬度標籤。
class ReplaceFormRow extends StatelessWidget {
  const ReplaceFormRow({
    super.key,
    required this.controller,
    this.label,
    this.hintText,
    this.validator,
    this.keyboardType,
    this.maxLines = 1,
    this.monospace = false,
  });

  final TextEditingController controller;
  final String? label;
  final String? hintText;
  final FormFieldValidator<String>? validator;
  final TextInputType? keyboardType;
  final int maxLines;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    final chrome = AppChrome.of(context);
    final scheme = Theme.of(context).colorScheme;
    final textStyle = (monospace ? AppTextStyles.bodySm : AppTextStyles.bodyBase)
        .copyWith(
          height: 1.3,
          color: scheme.onSurface,
          fontFamily: monospace ? 'monospace' : null,
        );
    final field = TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: textStyle,
      decoration: InputDecoration(
        isDense: true,
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        focusedErrorBorder: InputBorder.none,
        hintText: hintText,
        hintStyle: textStyle.copyWith(
          color: chrome.sectionText.withValues(alpha: 0.7),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      ),
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppGrouped.rowMinHeight),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppGrouped.rowPadding),
        child:
            label == null
                ? field
                : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.md),
                      child: SizedBox(
                        width: 96,
                        child: Text(
                          label!,
                          style: AppTextStyles.bodyBase.copyWith(
                            height: 1.3,
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                    Expanded(child: field),
                  ],
                ),
      ),
    );
  }
}
