import 'package:flutter/material.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
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
    final mono = _monospaceFieldStyle(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        GroupedSection(
          margin: margin,
          topGap: 0,
          children: [
            GroupedTextFieldRow(
              controller: nameCtrl,
              label: '規則名稱 *',
              validator: (v) => v!.trim().isEmpty ? '名稱不能為空' : null,
            ),
            GroupedTextFieldRow(controller: groupCtrl, label: '分組'),
            GroupedTextFieldRow(
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
            GroupedTextFieldRow(
              controller: patternCtrl,
              maxLines: 3,
              style: mono,
              // 不 trim：只有空白（含全形空格）的規則也是合法的替換內容。
              validator: (v) => v!.isEmpty ? '正則內容不能為空' : null,
            ),
          ],
        ),
        GroupedSection(
          margin: margin,
          header: '替換為內容',
          children: [
            GroupedTextFieldRow(
              controller: replacementCtrl,
              maxLines: 3,
              style: mono,
            ),
          ],
        ),
      ],
    );
  }
}

/// 正則、替換內容等程式碼欄位的等寬字樣式。
TextStyle _monospaceFieldStyle(BuildContext context) =>
    AppTextStyles.bodySm.copyWith(
      height: 1.3,
      color: Theme.of(context).colorScheme.onSurface,
      fontFamily: 'monospace',
    );
