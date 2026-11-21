import 'package:flutter/material.dart';
import 'package:night_reader/shared/widgets/text/ui_text.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/widgets/lists/grouped_list.dart';
import 'package:night_reader/core/chinese/ui_language.dart';

/// 規則除錯：輸入測試文字，即時顯示替換結果。
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
          children: [
            GroupedRow(title: '測試原文', showChevron: false),
            GroupedTextFieldRow(
              controller: testInputCtrl,
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
          children: [
            GroupedContent(
              // 結果是規則跑出來的字，照原文（ADR 0066）。
              child: UiText(
                testResult.isEmpty ? context.ui('(無結果)') : testResult,
                translate: false,
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
