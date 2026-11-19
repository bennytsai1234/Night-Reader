import 'package:flutter/material.dart';
import 'package:night_reader/shared/widgets/text/ui_text.dart';
import 'package:flutter/services.dart';
import 'package:night_reader/features/about/crash_log_page.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/popups/app_dialogs.dart';
import 'package:night_reader/shared/widgets/lists/grouped_list.dart';

/// 啟動失敗時的說明卡片：上方錯誤摘要，下方為分組動作列。
class StartupFailurePanel extends StatelessWidget {
  const StartupFailurePanel({
    super.key,
    required this.details,
    required this.onRetry,
    this.title = '啟動失敗',
    this.message = '初始化沒有完成，請重試或查看錯誤詳情。',
  });

  final String title;
  final String message;
  final String details;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chrome = AppChrome.of(context);

    return GroupedSection(
      margin: EdgeInsets.zero,
      topGap: 0,
      children: [
        GroupedContent(
          padding: const EdgeInsets.all(AppGrouped.rowPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.error_outline_rounded, color: scheme.error),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: UiText(
                      title,
                      style: AppTextStyles.titleMd.copyWith(
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              UiText(
                message,
                style: AppTextStyles.bodySm.copyWith(color: chrome.sectionText),
              ),
            ],
          ),
        ),
        GroupedRow(
          title: '重試',
          accent: true,
          showChevron: false,
          onTap: onRetry,
        ),
        GroupedRow(title: '錯誤詳情', onTap: () => _showDetails(context)),
        GroupedRow(
          title: '複製錯誤詳情',
          showChevron: false,
          onTap: () => _copyDetails(context),
        ),
        GroupedRow(
          title: '崩潰日誌',
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const CrashLogPage())),
        ),
      ],
    );
  }

  void _showDetails(BuildContext context) {
    showAppAlert<void>(
      context: context,
      title: '錯誤詳情',
      content: SelectableText(
        details,
        // 提示框裡的字一律 15（docs/design/components.md「選單與提示」）。
        style: const TextStyle(height: 1.45, fontFamily: 'monospace'),
      ),
      actions: const [
        AppAlertAction(label: '關閉', value: null, isDefault: true),
      ],
    );
  }

  Future<void> _copyDetails(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: details));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: UiText('已複製錯誤詳情')));
  }
}
