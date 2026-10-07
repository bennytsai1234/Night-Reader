import 'package:flutter/material.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';

/// 規則調試：輸入測試文字，即時顯示替換結果。
class ReplaceEditTestPanel extends StatelessWidget {
  final TextEditingController testInputCtrl;
  final String testResult;

  /// 分組卡片外距；放在已有左右內距的面板內時傳 [EdgeInsets.zero]。
  final EdgeInsetsGeometry? margin;

  const ReplaceEditTestPanel({
    super.key,
    required this.testInputCtrl,
    required this.testResult,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final chrome = AppChrome.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        GroupedSection(
          margin: margin,
          header: '規則調試',
          children: [
            GroupedTextFieldRow(
              controller: testInputCtrl,
              hintText: '請輸入要測試的內容',
              maxLines: 3,
              style: AppTextStyles.bodySm.copyWith(
                height: 1.3,
                color: scheme.onSurface,
              ),
            ),
          ],
        ),
        GroupedSection(
          margin: margin,
          topGap: AppSpacing.lg,
          header: '替換結果',
          children: [
            GroupedContent(
              child: Text(
                testResult.isEmpty ? '(無結果)' : testResult,
                style: AppTextStyles.bodySm.copyWith(
                  color: chrome.sectionText,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
